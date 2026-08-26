# frozen_string_literal: true

require "digest"
require "pathname"

module RubySkills
  # Validates, packages, and uploads a local skill to the registry.
  #
  # @example
  #   result = RubySkills::Publish.new("request-specs").run
  #   result.success?
  #
  # @since 0.1.0
  class Publish
    # @!attribute [rw] label
    #   @return [String] +namespace/name version+
    # @!attribute [rw] status
    #   @return [Symbol] +:published+, +:invalid+, +:unauthenticated+, +:conflict+, +:failed+
    # @!attribute [rw] failures
    #   @return [Array<String>]
    # @!attribute [rw] published
    #   @return [RubySkills::Registry::PublishedVersion, nil]
    # @!attribute [rw] error
    #   @return [String, nil]
    Result = Struct.new(:label, :status, :failures, :published, :error, keyword_init: true) do
      # @return [Boolean]
      def success?
        status == :published
      end
    end

    # @param path [String, Pathname]
    # @param client [RubySkills::Registry::Client]
    # @param output [String, Pathname]
    def initialize(path = ".", client: nil, output: "pkg")
      @path = Pathname.new(path)
      @client = client || Registry::Client.new
      @output = Pathname.new(output)
    end

    # @return [Result]
    def run
      validation = Validator.new(@path).validate
      return invalid(validation) unless validation.valid?
      return unauthenticated(validation) if @client.token.to_s.empty?

      manifest = Manifest.load(@path)
      artifact = build_artifact(manifest)
      verify_checksum!(artifact)
      published = upload(manifest, artifact)

      Result.new(
        label: validation.label,
        status: :published,
        failures: [],
        published: published,
        error: nil
      )
    rescue Registry::Error => e
      handle_registry_error(validation, e)
    end

    private

    # @param validation [RubySkills::Validator::Result]
    # @return [Result]
    def invalid(validation)
      Result.new(
        label: validation.label,
        status: :invalid,
        failures: validation.failures,
        published: nil,
        error: nil
      )
    end

    # @param validation [RubySkills::Validator::Result]
    # @return [Result]
    def unauthenticated(validation)
      Result.new(
        label: validation.label,
        status: :unauthenticated,
        failures: [],
        published: nil,
        error: nil
      )
    end

    # @param manifest [RubySkills::Manifest]
    # @return [RubySkills::Artifact::Result]
    def build_artifact(manifest)
      Artifact::Builder.new(
        root: manifest.root,
        manifest: manifest,
        destination: @output
      ).build
    end

    # @param artifact [RubySkills::Artifact::Result]
    # @return [void]
    # @raise [RubySkills::Error]
    def verify_checksum!(artifact)
      actual = Digest::SHA256.file(artifact.path).hexdigest
      return if actual.casecmp(artifact.checksum).zero?

      raise RubySkills::Error, "Checksum mismatch"
    end

    # @param manifest [RubySkills::Manifest]
    # @param artifact [RubySkills::Artifact::Result]
    # @return [RubySkills::Registry::PublishedVersion]
    def upload(manifest, artifact)
      @client.publish_version(
        name: manifest.full_name,
        version: manifest.version,
        checksum: artifact.checksum,
        manifest: manifest.to_h,
        artifact: artifact.path
      )
    end

    # @param validation [RubySkills::Validator::Result]
    # @param error [RubySkills::Registry::Error]
    # @return [Result]
    def handle_registry_error(validation, error)
      status = registry_status(error)
      Result.new(
        label: validation.label,
        status: status,
        failures: [],
        published: nil,
        error: error.message
      )
    end

    # @param error [RubySkills::Registry::Error]
    # @return [Symbol]
    def registry_status(error)
      return :conflict if error.code == "version_already_exists" || error.status == 409
      return :unauthenticated if error.code == "unauthenticated" || error.status == 401

      :failed
    end
  end
end
