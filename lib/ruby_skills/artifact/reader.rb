# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"
require "rubygems/package"
require "stringio"
require "zlib"

module RubySkills
  module Artifact
    # Reads a downloaded +.rskill+ and checks it before anything is extracted.
    #
    # The SHA-256 of the raw bytes is compared to the registry checksum
    # first. The gzip+tar archive is opened only after that match.
    #
    # @example
    #   artifact = RubySkills::Artifact::Reader.new(
    #     "rails-request-specs-1.4.2.rskill",
    #     expected_checksum: version.checksum
    #   )
    #   artifact.valid?
    #   artifact.manifest
    #   artifact.files
    #   artifact.checksum
    #   artifact.extract_to(".ruby-skills/rails/request-specs")
    #
    # @since 0.1.0
    class Reader
      # @param path [String, Pathname] +.rskill+ file
      # @param expected_checksum [String, nil] registry SHA-256 of the bytes
      def initialize(path, expected_checksum: nil)
        @path = Pathname.new(path)
        @expected_checksum = expected_checksum
      end

      # SHA-256 of the downloaded +.rskill+ bytes. Does not open the archive.
      #
      # @return [String] lowercase hex digest
      # @raise [RubySkills::Error] if the file cannot be read
      def checksum
        @checksum ||= Digest::SHA256.hexdigest(bytes)
      end

      # Whether the artifact matches the registry checksum (when given) and
      # contains a valid, extractable skill.
      #
      # @return [Boolean]
      def valid?
        verify_integrity!
        true
      rescue RubySkills::Error
        false
      end

      # +skill.yml+ parsed from the archive. Never writes to disk.
      #
      # @return [RubySkills::Manifest]
      # @raise [RubySkills::Error] on checksum mismatch or unreadable archive
      def manifest
        @manifest ||= load_manifest
      end

      # Archive members keyed by relative path. Unpacked in memory only after
      # the checksum matches.
      #
      # @return [Hash{String => String}] archive path => binary contents
      # @raise [RubySkills::Error] if the archive cannot be read
      def files
        verify_checksum!
        @files ||= unpack_members
      end

      # Extract every archive member under +destination+.
      #
      # Refuses to create or write files until the downloaded SHA-256 matches
      # the registry SHA-256 (when +expected_checksum+ was given).
      #
      # @param destination [String, Pathname]
      # @return [Pathname] expansion of +destination+
      # @raise [RubySkills::Error] on checksum mismatch, unsafe paths, or
      #   an invalid skill
      def extract_to(destination)
        verify_integrity!
        dest = Pathname.new(destination).expand_path
        FileUtils.mkdir_p(dest)

        files.each do |relative, content|
          target = safe_join(dest, relative)
          FileUtils.mkdir_p(target.dirname)
          target.binwrite(content)
        end

        dest
      end

      private

      # @return [String]
      def bytes
        return @bytes if defined?(@bytes)

        raise RubySkills::Error, "Artifact not found: #{@path}" unless @path.file?

        @bytes = @path.binread.b
      rescue Errno::ENOENT, Errno::EACCES => e
        raise RubySkills::Error, "could not read artifact: #{e.message}"
      end

      # @return [void]
      # @raise [RubySkills::Error]
      def verify_integrity!
        verify_checksum!
        unless files.key?(Manifest::FILENAME)
          raise RubySkills::Error, "skill.yml not found in artifact"
        end
        return if manifest.valid?

        raise RubySkills::Error, "invalid skill.yml in artifact"
      end

      # Compare downloaded bytes to the registry checksum before any unpack.
      #
      # @return [void]
      # @raise [RubySkills::Error]
      def verify_checksum!
        return if @expected_checksum.nil?
        return if checksum.casecmp(@expected_checksum.to_s).zero?

        raise RubySkills::Error, "Checksum mismatch"
      end

      # @return [RubySkills::Manifest]
      def load_manifest
        yaml = files[Manifest::FILENAME]
        raise RubySkills::Error, "skill.yml not found in artifact" unless yaml

        Manifest.from_yaml(yaml, members: files)
      end

      # @return [Hash{String => String}]
      def unpack_members
        members = {}
        gz = Zlib::GzipReader.new(StringIO.new(bytes))
        Gem::Package::TarReader.new(gz) do |tar|
          tar.each do |entry|
            next unless entry.file?

            assert_safe_member!(entry.full_name)
            members[entry.full_name] = entry.read.to_s.b
          end
        end
        members
      rescue Zlib::Error, Gem::Package::FormatError, ArgumentError => e
        raise RubySkills::Error, "could not read artifact: #{e.message}"
      ensure
        gz&.close
      end

      # @param relative [String]
      # @return [void]
      # @raise [RubySkills::Error]
      def assert_safe_member!(relative)
        path = Pathname.new(relative.to_s.tr("\\", "/"))
        return unless path.absolute? || relative.to_s.start_with?("/") ||
                      path.each_filename.include?("..")

        raise RubySkills::Error, "#{relative} escapes the skill directory"
      end

      # @param destination [Pathname]
      # @param relative [String]
      # @return [Pathname]
      # @raise [RubySkills::Error]
      def safe_join(destination, relative)
        assert_safe_member!(relative)

        target = destination.join(relative).expand_path
        target.ascend do |current|
          return target if current == destination
        end

        raise RubySkills::Error, "#{relative} escapes the skill directory"
      end
    end
  end
end
