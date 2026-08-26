# frozen_string_literal: true

require "fileutils"
require "pathname"
require "rubygems/package"
require "zlib"

module RubySkills
  module Artifact
    # Reads a +.rskill+ gzip+tar archive back into files.
    #
    # @example
    #   reader = RubySkills::Artifact::Reader.new("rails-request-specs-0.1.0.rskill")
    #   reader.files["skill.yml"]
    #   reader.extract_to("unpacked")
    #
    # @since 0.1.0
    class Reader
      # @param path [String, Pathname] +.rskill+ file
      def initialize(path)
        @path = Pathname.new(path)
      end

      # @return [Hash{String => String}] archive path => binary contents
      # @raise [RubySkills::Error] if the archive cannot be read
      def files
        @files ||= read_files
      end

      # Extract every archive member under +destination+.
      #
      # @param destination [String, Pathname]
      # @return [Pathname] expansion of +destination+
      # @raise [RubySkills::Error] if a member would escape +destination+
      def extract_to(destination)
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

      # @return [Hash{String => String}]
      def read_files
        members = {}

        Zlib::GzipReader.open(@path.to_s) do |gz|
          Gem::Package::TarReader.new(gz) do |tar|
            tar.each do |entry|
              next unless entry.file?

              members[entry.full_name] = entry.read
            end
          end
        end

        members
      rescue Zlib::Error, Gem::Package::FormatError, ArgumentError => e
        raise RubySkills::Error, "could not read artifact: #{e.message}"
      end

      # @param destination [Pathname]
      # @param relative [String]
      # @return [Pathname]
      # @raise [RubySkills::Error]
      def safe_join(destination, relative)
        path = Pathname.new(relative)
        if path.absolute? || path.each_filename.include?("..")
          raise RubySkills::Error, "#{relative} escapes the skill directory"
        end

        target = destination.join(relative).expand_path
        target.ascend do |current|
          return target if current == destination
        end

        raise RubySkills::Error, "#{relative} escapes the skill directory"
      end
    end
  end
end
