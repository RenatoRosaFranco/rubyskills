# frozen_string_literal: true

require "pathname"

module RubySkills
  module Artifact
    # Collects the files that belong in a +.rskill+ archive.
    #
    # Always includes +skill.yml+ and the configured entrypoint, plus every
    # regular file matched by +manifest.files+. Paths are normalized,
    # deduplicated, and rejected when they leave the skill root.
    #
    # @api private
    # @since 0.1.0
    class Fileset
      # @param root [Pathname]
      # @param manifest [RubySkills::Manifest]
      def initialize(root, manifest)
        @root = Pathname.new(root).expand_path
        @manifest = manifest
      end

      # @return [Array<(String, String)>] sorted +[archive_path, content]+ pairs
      # @raise [RubySkills::Error] on missing or unsafe paths
      def entries
        paths = Set.new
        add_required(paths, Manifest::FILENAME)
        add_required(paths, @manifest.entrypoint)
        add_globs(paths)

        paths.sort.map { |relative| [relative, read_file(relative)] }
      end

      private

      # @param paths [Set<String>]
      # @param relative [String]
      # @return [void]
      def add_required(paths, relative)
        raise RubySkills::Error, "#{relative} is required" if relative.to_s.empty?

        normalized = assert_safe_relative!(relative)
        unless packable_file?(@root.join(normalized))
          raise RubySkills::Error, "#{relative} does not exist"
        end

        paths << normalized
      end

      # @param paths [Set<String>]
      # @return [void]
      def add_globs(paths)
        patterns.each do |pattern|
          assert_safe_relative!(pattern)
          Dir.glob(pattern, base: @root.to_s).each do |match|
            normalized = assert_safe_relative!(match)
            next unless packable_file?(@root.join(normalized))

            paths << normalized
          end
        end
      end

      # @return [Array<String>]
      def patterns
        files = @manifest.files
        return [] unless files.is_a?(Array)

        files.select { |pattern| pattern.is_a?(String) && !pattern.empty? }
      end

      # @param relative [String]
      # @return [String] POSIX archive path
      # @raise [RubySkills::Error]
      def assert_safe_relative!(relative)
        path = normalize(relative)
        full = @root.join(path)
        return path unless full.exist? || full.symlink?

        raise RubySkills::Error, "#{relative} is an unsafe symlink" if unsafe_symlink?(full)

        unless inside_root?(full.realpath)
          raise RubySkills::Error, "#{relative} escapes the skill directory"
        end

        path
      end

      # @param relative [String]
      # @return [String]
      # @raise [RubySkills::Error]
      def normalize(relative)
        parts = posix_parts(relative)
        raise RubySkills::Error, "#{relative} escapes the skill directory" if parts.empty?

        parts.join("/")
      end

      # @param relative [String]
      # @return [Array<String>]
      # @raise [RubySkills::Error]
      def posix_parts(relative)
        path = relative_posix(relative)
        parts = path.split("/")
        raise RubySkills::Error, "#{relative} escapes the skill directory" if parts.include?("..")

        parts.reject! do |part|
          part.empty? || part == "."
        end
        parts
      end

      # @param relative [String]
      # @return [String]
      # @raise [RubySkills::Error]
      def relative_posix(relative)
        unless relative.is_a?(String) && !Pathname.new(relative).absolute? &&
               !relative.start_with?("/")
          raise RubySkills::Error, "#{relative} must be a relative path"
        end

        relative.tr("\\", "/")
      end

      # @param path [Pathname]
      # @return [Boolean]
      def unsafe_symlink?(path)
        path.ascend.any? do |current|
          break false if current == @root
          next false unless current.symlink?

          !inside_root?(current.realpath)
        end
      rescue Errno::ENOENT, Errno::ELOOP
        true
      end

      # @param path [Pathname]
      # @return [Boolean]
      def packable_file?(path)
        return false unless path.exist? || path.symlink?
        return false if unsafe_symlink?(path)

        path.file?
      end

      # @param relative [String]
      # @return [String]
      def read_file(relative)
        full = @root.join(relative)
        raise RubySkills::Error, "#{relative} is an unsafe symlink" if unsafe_symlink?(full)

        full.binread
      end

      # @param path [Pathname]
      # @return [Boolean]
      def inside_root?(path)
        base = @root.realpath
        path.ascend do |current|
          return true if current == base
        end
        false
      end
    end
  end
end
