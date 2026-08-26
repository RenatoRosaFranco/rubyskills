# frozen_string_literal: true

module RubySkills
  # Published +.rskill+ artifacts: gzip-compressed tar archives with
  # deterministic metadata so the same skill always yields the same SHA-256.
  #
  # @see RubySkills::Artifact::Builder
  # @see RubySkills::Artifact::Reader
  # @since 0.1.0
  module Artifact
    # Outcome of {Builder#build}.
    class Result
      # @return [Pathname] written +.rskill+ file
      attr_reader :path

      # @return [String] SHA-256 hex digest of the artifact bytes
      attr_reader :checksum

      # @return [Array<String>] normalized archive paths, sorted
      attr_reader :files

      # @return [Integer] artifact size in bytes
      attr_reader :size

      # @param path [Pathname]
      # @param checksum [String]
      # @param files [Array<String>]
      # @param size [Integer]
      def initialize(path:, checksum:, files:, size:)
        @path = path
        @checksum = checksum
        @files = files
        @size = size
      end
    end
  end
end
