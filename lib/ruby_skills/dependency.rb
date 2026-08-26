# frozen_string_literal: true

require "rubygems"

module RubySkills
  # A skill declared in a project {Skillfile}.
  #
  # @example
  #   dependency.name        # => "rails/request-specs"
  #   dependency.requirement # => Gem::Requirement.new("~> 2.0")
  #
  # @since 0.1.0
  class Dependency
    # @return [String] +namespace/name+
    attr_reader :name

    # @return [Gem::Requirement]
    attr_reader :requirement

    # @param name [String]
    # @param requirement [Gem::Requirement]
    def initialize(name:, requirement:)
      @name = name
      @requirement = requirement
    end

    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.is_a?(self.class) &&
        name == other.name &&
        requirement == other.requirement
    end
    alias eql? ==

    # @return [Integer]
    def hash
      [self.class, name, requirement].hash
    end
  end
end
