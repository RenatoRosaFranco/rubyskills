# frozen_string_literal: true

require "pathname"
require "yaml"
require "rubygems"

module RubySkills
  # Canonical representation of a local skill directory.
  #
  # Loads +skill.yml+, normalizes fields, and collects validation errors
  # without talking to the network or printing CLI output.
  #
  # @example Load a skill directory
  #   manifest = RubySkills::Manifest.load("my-skill")
  #   manifest.full_name # => "rails/request-specs"
  #   manifest.valid?
  #
  # @since 0.1.0
  class Manifest # rubocop:disable Metrics/ClassLength
    # Filename of the skill manifest inside a skill directory.
    FILENAME = "skill.yml"

    # Default +files+ glob when the field is omitted.
    DEFAULT_FILES = ["SKILL.md"].freeze

    # Allowed shape for +name+ and +namespace+.
    IDENTIFIER = /\A[a-z0-9_-]+\z/

    # @return [String, nil]
    attr_reader :name

    # @return [String, nil]
    attr_reader :namespace

    # @return [String, nil]
    attr_reader :version

    # @return [String, nil]
    attr_reader :summary

    # @return [String, nil]
    attr_reader :description

    # @return [Array<String>, Object]
    attr_reader :categories

    # @return [Array<String>, Object]
    attr_reader :tags

    # @return [Hash, Object]
    attr_reader :compatibility

    # @return [Array<String>, Object]
    attr_reader :files

    # @return [String, nil]
    attr_reader :entrypoint

    # @return [Array<String>] validation messages; empty when {#valid?}
    attr_reader :errors

    # Load +skill.yml+ from a skill directory or from the file itself.
    #
    # @param path [String, Pathname] skill directory or +skill.yml+ path
    # @return [Manifest]
    # @raise [RubySkills::Error] if the path or YAML cannot be read
    def self.load(path)
      new(path)
    end

    # @param path [String, Pathname] skill directory or +skill.yml+ path
    # @raise [RubySkills::Error] if the path or YAML cannot be read
    def initialize(path)
      @errors = []
      @root = resolve_root(path)
      @raw = read_yaml
      apply_fields
      validate
    end

    # @return [String] +namespace/name+
    def full_name
      "#{namespace}/#{name}"
    end

    # @return [Boolean] whether every field passed validation
    def valid?
      errors.empty?
    end

    # @return [Hash{String => Object}] serializable snapshot of the manifest
    def to_h
      {
        "name" => name,
        "namespace" => namespace,
        "version" => version,
        "summary" => summary,
        "description" => description,
        "categories" => categories,
        "tags" => tags,
        "compatibility" => compatibility,
        "files" => files,
        "entrypoint" => entrypoint,
        "full_name" => full_name
      }
    end

    private

    # @api private
    # @param path [String, Pathname]
    # @return [Pathname]
    # @raise [RubySkills::Error] if +path+ does not exist
    def resolve_root(path)
      pathname = Pathname.new(path).expand_path
      raise RubySkills::Error, "Skill path does not exist: #{pathname}" unless pathname.exist?

      pathname.directory? ? pathname : pathname.dirname
    end

    # @api private
    # @return [Hash]
    # @raise [RubySkills::Error] if +skill.yml+ is missing or not safe YAML
    def read_yaml
      yaml_path = @root.join(FILENAME)
      raise RubySkills::Error, "skill.yml not found in #{@root}" unless yaml_path.file?

      loaded = YAML.safe_load(
        yaml_path.read,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
      loaded.is_a?(Hash) ? loaded : {}
    rescue Psych::Exception => e
      raise RubySkills::Error, "Invalid skill.yml: #{e.message}"
    end

    # @api private
    # @return [void]
    def apply_fields
      @name = string_field("name")
      @namespace = string_field("namespace")
      @version = string_field("version")
      @summary = string_field("summary")
      @description = string_field("description")
      @entrypoint = string_field("entrypoint")
      @categories = @raw.key?("categories") ? @raw["categories"] : []
      @tags = @raw.key?("tags") ? @raw["tags"] : []
      @compatibility = @raw.key?("compatibility") ? @raw["compatibility"] : {}
      @files = @raw.key?("files") ? @raw["files"] : DEFAULT_FILES.dup
    end

    # @api private
    # @param key [String]
    # @return [String, nil]
    def string_field(key)
      value = @raw[key]
      return if value.nil?

      value.is_a?(String) ? value.strip : value
    end

    # @api private
    # @return [void]
    def validate
      validate_identifier(:name, @name)
      validate_identifier(:namespace, @namespace)
      validate_version
      validate_summary
      validate_entrypoint
      validate_string_array(:categories, @categories)
      validate_string_array(:tags, @tags)
      validate_compatibility
      validate_files
      validate_optional_string(:description, @description)
    end

    # @api private
    # @param field [Symbol]
    # @param value [Object]
    # @return [void]
    def validate_identifier(field, value)
      if blank_string?(value)
        @errors << "#{field} is required"
        return
      end

      return if value.is_a?(String) && value.match?(IDENTIFIER)

      @errors << "#{field} must be lowercase and contain only letters, " \
                 "numbers, '_' and '-'"
    end

    # @api private
    # @return [void]
    def validate_version
      if blank_string?(@version)
        @errors << "version is required"
        return
      end

      unless @version.is_a?(String) && Gem::Version.correct?(@version) &&
             !@version.strip.empty?
        @errors << "version is not a valid gem version"
      end
    end

    # @api private
    # @return [void]
    def validate_summary
      if blank_string?(@summary)
        @errors << "summary is required"
        return
      end

      @errors << "summary must be a non-empty string" unless @summary.is_a?(String)
    end

    # @api private
    # @return [void]
    def validate_entrypoint
      if blank_string?(@entrypoint)
        @errors << "entrypoint is required"
        return
      end

      unless @entrypoint.is_a?(String)
        @errors << "entrypoint must be a relative path"
        return
      end

      path = Pathname.new(@entrypoint)
      if path.absolute?
        @errors << "entrypoint must be a relative path"
        return
      end

      if path.each_filename.include?("..")
        @errors << "entrypoint must not contain path traversal"
        return
      end

      target = @root.join(path).expand_path
      unless inside_root?(target)
        @errors << "entrypoint must not contain path traversal"
        return
      end

      return if target.file?

      @errors << "entrypoint file does not exist: #{@entrypoint}"
    end

    # @api private
    # @param field [Symbol]
    # @param value [Object]
    # @return [void]
    def validate_string_array(field, value)
      return if value.is_a?(Array) && value.all?(String)

      @errors << "#{field} must be an array of strings"
    end

    # @api private
    # @return [void]
    def validate_compatibility
      @errors << "compatibility must be a hash" unless @compatibility.is_a?(Hash)
    end

    # @api private
    # @return [void]
    def validate_files
      return if @files.is_a?(Array) && @files.all?(String)

      @errors << "files must be an array of glob patterns"
    end

    # @api private
    # @param field [Symbol]
    # @param value [Object]
    # @return [void]
    def validate_optional_string(field, value)
      return if value.nil? || value.is_a?(String)

      @errors << "#{field} must be a string"
    end

    # @api private
    # @param value [Object]
    # @return [Boolean]
    def blank_string?(value)
      value.nil? || (value.is_a?(String) && value.empty?)
    end

    # @api private
    # @param path [Pathname]
    # @return [Boolean]
    def inside_root?(path)
      root = @root.expand_path
      path.ascend do |current|
        return true if current == root
      end
      false
    end
  end
end
