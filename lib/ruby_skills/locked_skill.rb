# frozen_string_literal: true

require "rubygems"

module RubySkills
  # An exact skill version recorded in {Lockfile}.
  #
  # +dependencies+ are the runtime requirements of this locked version.
  #
  # @example
  #   locked.version   # => Gem::Version.new("1.3.2")
  #   locked.checksum  # => "sha256:93b28ae0..."
  #
  # @since 0.1.0
  class LockedSkill
    attr_reader :name

    # @return [Gem::Version]
    attr_reader :version

    # @return [String] +sha256:<hex>+
    attr_reader :checksum

    # @return [Array<Dependency>] runtime dependencies of this locked version
    attr_reader :dependencies

    # @param name [String]
    # @param version [Gem::Version, String]
    # @param checksum [String]
    # @param dependencies [Array<Dependency>]
    def initialize(name:, version:, checksum:, dependencies: [])
      @name = name
      @version = version.is_a?(Gem::Version) ? version : Gem::Version.new(version)
      @checksum = checksum
      @dependencies = Array(dependencies).sort_by(&:name).freeze
    end

    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.is_a?(self.class) &&
        name == other.name &&
        version == other.version &&
        checksum == other.checksum &&
        dependencies == other.dependencies
    end
  end
end
