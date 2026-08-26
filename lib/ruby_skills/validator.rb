# frozen_string_literal: true

require "pathname"

module RubySkills
  # Validates a local skill directory without network access or file mutation.
  #
  # Runs {RubySkills::Manifest} checks, then filesystem checks (entrypoint
  # existence is part of the manifest; glob safety and included-file counts
  # are filesystem concerns).
  #
  # @example
  #   result = RubySkills::Validator.new("request-specs").validate
  #   result.valid?
  #
  # @since 0.1.0
  class Validator # rubocop:disable Metrics/ClassLength
    # @!attribute [rw] label
    #   @return [String] text used in +Validating ...+
    # @!attribute [rw] failures
    #   @return [Array<String>] field-level error messages
    # @!attribute [rw] file_count
    #   @return [Integer] files matched by safe +files+ globs
    Result = Struct.new(:label, :failures, :file_count, keyword_init: true) do
      # @return [Boolean]
      def valid?
        failures.empty?
      end
    end

    # @param path [String, Pathname] skill directory or +skill.yml+ path
    def initialize(path = ".")
      @path = Pathname.new(path)
    end

    # @return [Result]
    def validate
      manifest = Manifest.load(@path)
      failures = []
      failures.concat(manifest_failures(manifest))
      failures.concat(version_failures(manifest))
      failures.concat(entrypoint_failures(manifest))
      file_count, file_failures = files_report(manifest)
      failures.concat(file_failures)

      Result.new(
        label: label_for(manifest),
        failures: failures.uniq,
        file_count: file_count
      )
    rescue RubySkills::Error => e
      Result.new(label: "skill", failures: [e.message], file_count: 0)
    end

    private

    # @api private
    # @param manifest [RubySkills::Manifest]
    # @return [String]
    def label_for(manifest)
      identifiable?(manifest) ? "#{manifest.full_name} #{manifest.version}".strip : "skill"
    end

    # @api private
    # @param manifest [RubySkills::Manifest]
    # @return [Boolean]
    def identifiable?(manifest)
      [manifest.name, manifest.namespace].all? do |value|
        value.is_a?(String) && value.match?(Manifest::IDENTIFIER)
      end
    end

    # @api private
    # @param manifest [RubySkills::Manifest]
    # @return [Array<String>]
    def manifest_failures(manifest)
      manifest.errors.reject do |error|
        error.start_with?("version ", "entrypoint ")
      end
    end

    # @api private
    # @param manifest [RubySkills::Manifest]
    # @return [Array<String>]
    def version_failures(manifest)
      return [] if version_ok?(manifest)

      if manifest.version.to_s.empty?
        ["version is required"]
      else
        [%(version: "#{manifest.version}" is invalid)]
      end
    end

    # @api private
    # @param manifest [RubySkills::Manifest]
    # @return [Boolean]
    def version_ok?(manifest)
      manifest.version.is_a?(String) &&
        !manifest.version.empty? &&
        Gem::Version.correct?(manifest.version)
    end

    # @api private
    # @param manifest [RubySkills::Manifest]
    # @return [Array<String>]
    def entrypoint_failures(manifest)
      entrypoint = manifest.entrypoint
      return ["entrypoint is required"] if entrypoint.to_s.empty?
      return ["entrypoint must be a relative path"] unless entrypoint.is_a?(String)

      path = Pathname.new(entrypoint)
      if path.absolute? || path.each_filename.include?("..")
        return [%(entrypoint: #{entrypoint} escapes the skill directory)]
      end

      target = manifest.root.join(path).expand_path
      unless inside_root?(target, manifest.root)
        return [%(entrypoint: #{entrypoint} escapes the skill directory)]
      end

      return [] if target.file?

      [%(entrypoint: #{entrypoint} does not exist)]
    end

    # @api private
    # @param manifest [RubySkills::Manifest]
    # @return [Array(Integer, Array<String>)]
    def files_report(manifest)
      return [0, []] unless glob_list?(manifest.files)

      count = 0
      failures = []

      manifest.files.each do |pattern|
        unsafe = unsafe_matches(manifest, pattern)
        if unsafe.any?
          failures.concat(unsafe)
          next
        end

        count += counted_files(manifest, pattern)
      end

      [count, failures.uniq]
    end

    # @api private
    # @param files [Object]
    # @return [Boolean]
    def glob_list?(files)
      files.is_a?(Array) && files.all?(String)
    end

    # @api private
    # @param manifest [RubySkills::Manifest]
    # @param pattern [String]
    # @return [Array<String>]
    def unsafe_matches(manifest, pattern)
      return [%(files: #{pattern} escapes the skill directory)] if pattern_escapes?(pattern)

      Dir.glob(pattern, base: manifest.root.to_s).filter_map do |relative|
        full = manifest.root.join(relative).expand_path
        next unless pattern_escapes?(relative) || !inside_root?(full, manifest.root)

        %(files: #{pattern} escapes the skill directory)
      end
    end

    # @api private
    # @param manifest [RubySkills::Manifest]
    # @param pattern [String]
    # @return [Integer]
    def counted_files(manifest, pattern)
      Dir.glob(pattern, base: manifest.root.to_s).count do |relative|
        manifest.root.join(relative).expand_path.file?
      end
    end

    # @api private
    # @param pattern [String]
    # @return [Boolean]
    def pattern_escapes?(pattern)
      path = Pathname.new(pattern)
      path.absolute? || path.each_filename.include?("..")
    end

    # @api private
    # @param path [Pathname]
    # @param root [Pathname]
    # @return [Boolean]
    def inside_root?(path, root)
      base = root.expand_path
      path.ascend do |current|
        return true if current == base
      end
      false
    end
  end
end
