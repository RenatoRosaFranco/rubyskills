# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tmpdir"

module RubySkills
  # Downloads a published skill and extracts it into +.ruby-skills+.
  #
  # Direct install does not read a Skillfile or write +Skills.lock+.
  # Project-level Skillfile installs use {ProjectInstall}.
  #
  # @example
  #   result = RubySkills::Install.new("rails/request-specs").run
  #   result.path # => .ruby-skills/rails/request-specs/1.4.2
  #
  # @since 0.1.0
  class Install # rubocop:disable Metrics/ClassLength
    Result = Struct.new(:name, :version, :checksum, :path, :error, keyword_init: true) do
      # @return [Boolean]
      def success?
        error.nil? && path
      end
    end

    class << self
      # Canonical on-disk path for a published skill version.
      #
      # @param name [String]
      # @param version [Gem::Version, String]
      # @param config [Config]
      # @return [Pathname]
      def destination(name, version, config:)
        namespace, skill = split_name(name)
        config.skills_path.join(namespace, skill, version.to_s)
      end

      # @param name [String]
      # @param version [Gem::Version, String]
      # @param config [Config]
      # @return [Boolean]
      def installed?(name, version, config:)
        destination(name, version, config: config).directory?
      end

      # Installed version directory names for +name+ under +.ruby-skills+.
      #
      # @param name [String]
      # @param config [Config]
      # @return [Array<String>]
      def installed_versions(name, config:)
        namespace, skill = split_name(name)
        dir = config.skills_path.join(namespace, skill)
        return [] unless dir.directory?
        return [] if dir.symlink?

        dir.children.filter_map { |child|
          next unless child.directory?
          next if child.symlink?
          next if child.basename.to_s.start_with?(".")

          child.basename.to_s
        }.sort
      end

      # Raise if +name+/+version+ would escape canonical storage.
      #
      # Missing destinations are allowed (nothing to remove).
      #
      # @param name [String]
      # @param version [Gem::Version, String]
      # @param config [Config]
      # @return [void]
      # @raise [RubySkills::Error]
      def assert_removable!(name, version, config:)
        dest = destination(name, version, config: config)
        assert_safe_component!(version)
        assert_under_skills!(dest, config)
        return unless dest.exist? || dest.symlink?

        assert_safe_entry!(dest, config)
      end

      # Delete one installed version and prune empty parent directories.
      #
      # Never removes +.ruby-skills+ itself. Never follows a symlink that
      # points outside canonical storage.
      #
      # @param name [String]
      # @param version [Gem::Version, String]
      # @param config [Config]
      # @return [void]
      def remove_version!(name, version, config:)
        dest = destination(name, version, config: config)
        assert_removable!(name, version, config: config)
        return unless dest.exist? || dest.symlink?

        remove_tree_safely(dest, config)
        prune_empty_parents(dest, stop_at: config.skills_path)
      end

      # Compare two SHA-256 values, with or without a +sha256:+ prefix.
      #
      # @param actual [String]
      # @param expected [String]
      # @return [void]
      # @raise [RubySkills::Error]
      def verify_checksum!(actual, expected)
        left = hex_digest(actual)
        right = hex_digest(expected)
        return if left.casecmp(right).zero?

        raise RubySkills::Error, "Checksum mismatch"
      end

      # Verify +bytes+ against +checksum+ and extract into +destination+.
      #
      # @param bytes [String]
      # @param checksum [String]
      # @param destination [Pathname]
      # @return [String] lowercase SHA-256 of the artifact
      def extract(bytes:, checksum:, destination:)
        Dir.mktmpdir("ruby-skills-") do |dir|
          archive = Pathname.new(dir).join("artifact.rskill")
          archive.binwrite(bytes)
          reader = Artifact::Reader.new(archive, expected_checksum: checksum)
          extract_atomically(reader, destination)
          reader.checksum
        end
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

      # @param reader [Artifact::Reader]
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

      # @param value [String]
      # @return [String]
      def hex_digest(value)
        value.to_s.strip.delete_prefix("sha256:")
      end

      # @param value [Gem::Version, String]
      # @return [void]
      def assert_safe_component!(value)
        text = value.to_s
        if text.empty? || text.start_with?(".") || text.include?("/") ||
           text.include?("\\") || text.include?("..")
          raise RubySkills::Error, "Refusing to remove unsafe path #{text.inspect}"
        end
      end

      # @param path [Pathname]
      # @param config [Config]
      # @return [void]
      def assert_under_skills!(path, config)
        root = config.skills_path.expand_path
        expanded = path.expand_path
        return if under?(expanded, root)

        raise RubySkills::Error, "Refusing to remove #{path} (outside .ruby-skills)"
      end

      # @param path [Pathname]
      # @param config [Config]
      # @return [void]
      def assert_safe_entry!(path, config)
        assert_under_skills!(path, config)
        return unless path.symlink?

        target = Pathname.new(path.readlink)
        target = path.dirname.join(target) unless target.absolute?
        return if under?(target.expand_path, config.skills_path.expand_path)

        raise RubySkills::Error,
              "Refusing to follow symlink #{path} outside .ruby-skills"
      end

      # @param path [Pathname]
      # @param root [Pathname]
      # @return [Boolean]
      def under?(path, root)
        path == root || path.to_s.start_with?("#{root}/")
      end

      # @param path [Pathname]
      # @param config [Config]
      # @return [void]
      def remove_tree_safely(path, config)
        assert_safe_entry!(path, config)
        if path.symlink? || path.file?
          path.unlink
          return
        end
        return unless path.directory?

        path.children.each do |child|
          remove_tree_safely(child, config)
        end
        path.rmdir
      end

      # @param removed_path [Pathname]
      # @param stop_at [Pathname]
      # @return [void]
      def prune_empty_parents(removed_path, stop_at:)
        dir = removed_path.dirname
        stop = stop_at.expand_path
        while under?(dir.expand_path, stop) && dir.expand_path != stop
          break unless dir.directory?
          break if dir.symlink?
          break unless dir.children.empty?

          dir.rmdir
          dir = dir.dirname
        end
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
    # @return [Array(String, Pathname)]
    def install_version(version)
      download = @client.download(version.name, version.version)
      self.class.verify_checksum!(download.checksum, version.checksum)
      destination = self.class.destination(version.name, version.version, config: @config)
      checksum = self.class.extract(
        bytes: download.bytes,
        checksum: version.checksum,
        destination: destination
      )
      [checksum, destination]
    end
  end
end
