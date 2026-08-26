# frozen_string_literal: true

require "fileutils"
require "pathname"
require "yaml"

module RubySkills
  # Registry API token stored in +credentials.yml+, never in +config.yml+.
  #
  # The file lives next to user config and is written +0600+; the directory is
  # +0700+.
  #
  # @example
  #   RubySkills::Credentials.load.update_token!("rsk_...")
  #   RubySkills::Credentials.load.token
  #
  # @since 0.1.0
  class Credentials
    FILENAME = "credentials.yml"
    FILE_MODE = 0o600
    DIRECTORY_MODE = 0o700

    # @return [Pathname]
    def self.path
      UserConfig.directory.join(FILENAME)
    end

    # @param directory [String, Pathname, nil]
    # @return [Credentials]
    def self.load(directory: nil)
      new(directory: directory || UserConfig.directory).tap(&:read)
    end

    # @param directory [String, Pathname]
    def initialize(directory: UserConfig.directory)
      @directory = Pathname.new(directory)
      @data = {}
    end

    # @return [Pathname]
    def path
      @directory.join(FILENAME)
    end

    # @return [Credentials]
    def read
      @data = load_yaml
      self
    end

    # @return [String, nil]
    def token
      value = @data["token"].to_s.strip
      value.empty? ? nil : value
    end

    # @param token [String]
    # @return [void]
    # @raise [RubySkills::Error] if +token+ is blank
    def update_token!(token)
      raw = token.to_s.strip
      raise RubySkills::Error, "Token is required" if raw.empty?

      @data["token"] = raw
      save
    end

    # Remove the saved token.
    #
    # @return [void]
    def clear!
      @data.delete("token")
      if @data.empty?
        path.delete if path.file?
      else
        save
      end
    end

    # @return [String]
    def inspect
      masked = token ? "[FILTERED]" : "nil"
      "#<#{self.class.name} path=#{path} token=#{masked}>"
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
      raise RubySkills::Error, "Invalid credentials.yml: #{e.message}"
    end

    # @return [void]
    def save
      FileUtils.mkdir_p(@directory)
      @directory.chmod(DIRECTORY_MODE) if @directory.directory?
      path.write(YAML.dump(stringify_keys(@data)))
      path.chmod(FILE_MODE)
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
