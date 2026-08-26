# frozen_string_literal: true

require "rubygems"

module RubySkills
  # One skill chosen by {Resolver}: exact version, checksum, and download info.
  #
  # @example
  #   resolved.version      # => Gem::Version.new("1.3.2")
  #   resolved.checksum     # => "sha256:93b28ae0..."
  #   resolved.download_url
  #
  # @since 0.1.0
  class ResolvedSkill
    # @return [String] +namespace/name+
    attr_reader :name

    # @return [Gem::Version]
    attr_reader :version

    # @return [String] +sha256:<hex>+
    attr_reader :checksum

    # @return [String, nil] registry artifact URL
    attr_reader :download_url

    # @return [String] registry origin
    attr_reader :source

    # @return [Array<Dependency>] runtime dependencies of this skill version
    attr_reader :dependencies

    # @return [Array<Resolver::Term>] why this skill is in the graph
    attr_reader :required_by

    # @param name [String]
    # @param version [Gem::Version, String]
    # @param checksum [String]
    # @param download_url [String, nil]
    # @param source [String]
    # @param dependencies [Array<Dependency>]
    # @param required_by [Array<Resolver::Term>]
    def initialize( # rubocop:disable Metrics/ParameterLists
      name:, version:, checksum:, source:,
      download_url: nil, dependencies: [], required_by: []
    )
      @name = name
      @version = version.is_a?(Gem::Version) ? version : Gem::Version.new(version)
      @checksum = self.class.normalize_checksum(checksum)
      @download_url = download_url
      @source = source
      @dependencies = Array(dependencies).freeze
      @required_by = Array(required_by).freeze
    end

    # @param value [String]
    # @return [String]
    def self.normalize_checksum(value)
      hex = value.to_s.strip.delete_prefix("sha256:").downcase
      "sha256:#{hex}"
    end

    # @return [String] lowercase hex without the +sha256:+ prefix
    def checksum_hex
      checksum.delete_prefix("sha256:")
    end

    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.is_a?(self.class) &&
        name == other.name &&
        version == other.version &&
        checksum == other.checksum &&
        download_url == other.download_url &&
        source == other.source &&
        dependencies == other.dependencies
    end
  end
end
