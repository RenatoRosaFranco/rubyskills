# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tmpdir"

module RubySkills
  # Downloads a published skill and extracts it into +.ruby-skills+.
  #
  # Does not read a Skillfile, write +Skills.lock+, or sync editor adapters.
  # The install is identified by namespace, name, version, and SHA-256 of the
  # downloaded +.rskill+ bytes.
  #
  # @example
  #   result = RubySkills::Install.new("rails/request-specs").run
  #   result.path # => .ruby-skills/rails/request-specs/1.4.2
  #
  # @since 0.1.0
  class Install
    Result = Struct.new(:name, :version, :checksum, :path, :error, keyword_init: true) do
      # @return [Boolean]
      def success?
        error.nil? && path
      end
    end

    # @param name [String] +namespace/skill+
    # @param client [RubySkills::Registry::Client]
    # @param config [RubySkills::Config]
    def initialize(name, client: nil, config: nil)
      @name = name
      @client = client || Registry::Client.new
      @config = config || Config.new
    end

    # Resolve, download, verify, and extract the skill.
    #
    # @return [Result]
    def run
      resolved = @client.resolve_version(@name, "latest")
      checksum, path = install_version(resolved)

      Result.new(
        name: resolved.name,
        version: resolved.version,
        checksum: checksum,
        path: path,
        error: nil
      )
    rescue RubySkills::Error => e
      Result.new(
        name: @name,
        version: resolved&.version,
        checksum: nil,
        path: nil,
        error: e
      )
    end

    private

    # @param version [RubySkills::Registry::Version]
    # @return [Array(String, Pathname)] checksum and install directory
    def install_version(version)
      download = @client.download(version.name, version.version)
      destination = install_path(version)

      Dir.mktmpdir("ruby-skills-") do |dir|
        archive = Pathname.new(dir).join(archive_name(version))
        archive.binwrite(download.bytes)
        reader = Artifact::Reader.new(archive, expected_checksum: version.checksum)
        extract_atomically(reader, destination)
        [reader.checksum, destination]
      end
    end

    # @param version [RubySkills::Registry::Version]
    # @return [Pathname]
    def install_path(version)
      namespace, skill = split_name(version.name)
      @config.skills_path.join(namespace, skill, version.version)
    end

    # @param version [RubySkills::Registry::Version]
    # @return [String]
    def archive_name(version)
      namespace, skill = split_name(version.name)
      "#{namespace}-#{skill}-#{version.version}.rskill"
    end

    # @param name [String]
    # @return [Array(String, String)]
    def split_name(name)
      namespace, skill, extra = name.to_s.split("/", 3)
      if extra || namespace.to_s.empty? || skill.to_s.empty?
        raise RubySkills::Error, "#{name.inspect} must be namespace/name"
      end

      [namespace, skill]
    end

    # Extract to a staging directory, then replace the destination.
    #
    # @param reader [RubySkills::Artifact::Reader]
    # @param destination [Pathname]
    # @return [void]
    def extract_atomically(reader, destination)
      staging = destination.dirname.join(".tmp-#{destination.basename}-#{Process.pid}")
      FileUtils.rm_rf(staging)
      reader.extract_to(staging)
      FileUtils.mkdir_p(destination.dirname)
      FileUtils.rm_rf(destination)
      FileUtils.mv(staging, destination)
    ensure
      FileUtils.rm_rf(staging) if staging&.exist?
    end
  end
end
