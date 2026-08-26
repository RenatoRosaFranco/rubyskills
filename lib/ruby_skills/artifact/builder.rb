# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"

module RubySkills
  module Artifact
    # Builds a deterministic +.rskill+ archive from a local skill directory.
    #
    # @example
    #   result = RubySkills::Artifact::Builder.new(
    #     root: skill_root,
    #     manifest: manifest
    #   ).build
    #   result.path      # => #<Pathname rails-request-specs-0.1.0.rskill>
    #   result.checksum  # => SHA-256 of the artifact bytes
    #
    # @since 0.1.0
    class Builder
      # @param root [String, Pathname] skill directory
      # @param manifest [RubySkills::Manifest]
      # @param destination [String, Pathname, nil] directory for the +.rskill+
      def initialize(root:, manifest:, destination: nil)
        @root = Pathname.new(root).expand_path
        @manifest = manifest
        @destination = Pathname.new(destination || Dir.pwd).expand_path
      end

      # Package the skill and write +namespace-name-version.rskill+.
      #
      # @return [RubySkills::Artifact::Result]
      # @raise [RubySkills::Error] if the skill cannot be packed safely
      def build
        entries = Fileset.new(@root, @manifest).entries
        bytes = Archive.pack(entries)
        path = write(bytes)

        Result.new(
          path: path,
          checksum: Digest::SHA256.hexdigest(bytes),
          files: entries.map(&:first),
          size: bytes.bytesize
        )
      end

      private

      # @return [String]
      def filename
        "#{@manifest.namespace}-#{@manifest.name}-#{@manifest.version}.rskill"
      end

      # @param bytes [String]
      # @return [Pathname]
      def write(bytes)
        FileUtils.mkdir_p(@destination)
        path = @destination.join(filename)
        path.binwrite(bytes)
        path
      end
    end
  end
end
