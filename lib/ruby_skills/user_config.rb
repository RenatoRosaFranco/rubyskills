# frozen_string_literal: true

require "fileutils"
require "pathname"
require "uri"
require "yaml"

module RubySkills
  # User-level settings in +$XDG_CONFIG_HOME/ruby-skills/config.yml+.
  #
  # Used before login so the CLI can target localhost or staging:
  #
  #   registry: https://rubyskills.org
  #
  # @example Point the client at staging
  #   config = RubySkills::UserConfig.load
  #   config.update_registry!("https://staging.rubyskills.org")
  #
  # @since 0.1.0
  class UserConfig
    FILENAME = "config.yml"
    APP_DIRECTORY = "ruby-skills"

    # @return [Pathname] +~/.config/ruby-skills+ (or +$XDG_CONFIG_HOME/ruby-skills+)
    def self.directory
      xdg = ENV.fetch("XDG_CONFIG_HOME", nil).to_s.strip
      base = if xdg.empty?
               Pathname.new(Dir.home).join(".config")
             else
               Pathname.new(xdg)
             end
      base.join(APP_DIRECTORY)
    end

    # @return [Pathname]
    def self.path
      directory.join(FILENAME)
    end

    # @param directory [String, Pathname, nil]
    # @return [UserConfig]
    def self.load(directory: nil)
      new(directory: directory || self.directory).tap(&:read)
    end

    # @param directory [String, Pathname]
    def initialize(directory: self.class.directory)
      @directory = Pathname.new(directory)
      @data = {}
    end

    # @return [Pathname]
    def path
      @directory.join(FILENAME)
    end

    # @return [UserConfig]
    def read
      @data = load_yaml
      self
    end

    # Registry origin, defaulting to production.
    #
    # @return [String]
    def registry
      value = @data["registry"].to_s.strip
      value.empty? ? Registry::DEFAULT_URL : value.chomp("/")
    end

    # Persist a registry origin (http or https).
    #
    # @param url [String]
    # @return [String] stored origin
    # @raise [RubySkills::Error] if +url+ is not an http(s) origin
    def update_registry!(url)
      @data["registry"] = normalize_registry(url)
      save
      registry
    end

    # @return [void]
    def save
      FileUtils.mkdir_p(@directory, mode: 0o700)
      path.write(YAML.dump(stringify_keys(@data)))
      path.chmod(0o600)
    end

    private

    # @return [Hash{String => Object}]
    def load_yaml
      return {} unless path.file?

      loaded = YAML.safe_load(
        path.read,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
      loaded.is_a?(Hash) ? stringify_keys(loaded) : {}
    rescue Psych::Exception => e
      raise RubySkills::Error, "Invalid config.yml: #{e.message}"
    end

    # @param url [String]
    # @return [String]
    # @raise [RubySkills::Error]
    def normalize_registry(url)
      raw = url.to_s.strip
      uri = URI.parse(raw)
      unless uri.is_a?(URI::HTTP) && uri.host
        raise RubySkills::Error, "Invalid registry URL: #{url}"
      end

      raw.chomp("/")
    rescue URI::InvalidURIError
      raise RubySkills::Error, "Invalid registry URL: #{url}"
    end

    # @param data [Hash]
    # @return [Hash{String => Object}]
    def stringify_keys(data)
      data.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value
      end
    end
  end
end
