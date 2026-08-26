# frozen_string_literal: true

require "pathname"

module RubySkills
  # Validates a local skill and writes a deterministic +.rskill+ artifact.
  #
  # Does not create an archive when validation fails.
  #
  # @example
  #   result = RubySkills::Build.new("request-specs").run
  #   result.artifact.path
  #
  # @since 0.1.0
  class Build
    # @!attribute [rw] label
    #   @return [String] +namespace/name version+ shown in CLI output
    # @!attribute [rw] failures
    #   @return [Array<String>] validation messages when the build is skipped
    # @!attribute [rw] artifact
    #   @return [RubySkills::Artifact::Result, nil]
    # @!attribute [rw] output_path
    #   @return [String, nil] display path of the written archive
    Result = Struct.new(:label, :failures, :artifact, :output_path, keyword_init: true) do
      # @return [Boolean]
      def success?
        failures.empty? && artifact
      end

      # @return [Integer]
      def file_count
        artifact ? artifact.files.size : 0
      end
    end

    # @param path [String, Pathname] skill directory or +skill.yml+
    # @param output [String, Pathname] directory for the +.rskill+
    def initialize(path = ".", output: "pkg")
      @path = Pathname.new(path)
      @output = Pathname.new(output)
    end

    # @return [Result]
    def run
      validation = Validator.new(@path).validate
      return failed(validation) unless validation.valid?

      manifest = Manifest.load(@path)
      artifact = Artifact::Builder.new(
        root: manifest.root,
        manifest: manifest,
        destination: @output
      ).build

      Result.new(
        label: validation.label,
        failures: [],
        artifact: artifact,
        output_path: @output.join(artifact.path.basename).to_s
      )
    end

    private

    # @param validation [RubySkills::Validator::Result]
    # @return [Result]
    def failed(validation)
      Result.new(
        label: validation.label,
        failures: validation.failures,
        artifact: nil,
        output_path: nil
      )
    end
  end
end
