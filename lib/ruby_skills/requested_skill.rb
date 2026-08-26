# frozen_string_literal: true

require "rubygems"

module RubySkills
  # A skill name plus the requirement +install --save+ should persist.
  #
  # Parses +namespace/name+, +namespace/name@2.1.4+, and an explicit
  # +--version+ string. Default (optimistic) requirements are filled in after
  # resolution by {Skillfile.pessimistic_requirement}.
  #
  # @since 0.1.0
  class RequestedSkill
    # @return [String]
    attr_reader :name

    # @return [String, nil] explicit requirement to write, or +nil+ for default
    attr_reader :requirement_string

    # @param name [String]
    # @param requirement_string [String, nil]
    # @param explicit [Boolean]
    def initialize(name:, requirement_string: nil, explicit: false)
      @name = name
      @requirement_string = requirement_string
      @explicit = explicit
    end

    # @return [Boolean] true when the user supplied @version or --version
    def explicit?
      @explicit
    end

    # @param identifier [String] +namespace/name+ or +namespace/name@2.1.4+
    # @param version [String, nil] +--version+ value
    # @return [RequestedSkill]
    # @raise [RubySkills::Error]
    def self.parse(identifier, version: nil)
      name, at_version = split_identifier(identifier)
      unless valid_name?(name)
        raise RubySkills::Error, "#{identifier.inspect} must be namespace/name"
      end

      explicit_version = blank_to_nil(version)
      if explicit_version && at_version
        raise RubySkills::Error, "Pass either @version or --version, not both"
      end

      build(name, at_version: at_version, explicit_version: explicit_version)
    end

    # @param name [String]
    # @param at_version [String, nil]
    # @param explicit_version [String, nil]
    # @return [RequestedSkill]
    def self.build(name, at_version:, explicit_version:)
      if explicit_version
        new(
          name: name,
          requirement_string: parsed_requirement_string(explicit_version),
          explicit: true
        )
      elsif at_version
        exact(name, at_version)
      else
        new(name: name)
      end
    end
    private_class_method :build

    # @param name [String]
    # @param at_version [String]
    # @return [RequestedSkill]
    def self.exact(name, at_version)
      unless Gem::Version.correct?(at_version)
        raise RubySkills::Error, "Invalid version #{at_version.inspect}"
      end

      new(name: name, requirement_string: "= #{at_version}", explicit: true)
    end
    private_class_method :exact

    # @param identifier [String]
    # @return [Array(String, String, nil)]
    def self.split_identifier(identifier)
      raw = identifier.to_s.strip
      name, at_version = raw.split("@", 2)
      at_version = nil if at_version && at_version.empty?
      [name.to_s, at_version]
    end
    private_class_method :split_identifier

    # @param value [String, nil]
    # @return [String, nil]
    def self.blank_to_nil(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
    private_class_method :blank_to_nil

    # @param name [String]
    # @return [Boolean]
    def self.valid_name?(name)
      namespace, skill, extra = name.split("/", 3)
      extra.nil? &&
        namespace.to_s.match?(Manifest::IDENTIFIER) &&
        skill.to_s.match?(Manifest::IDENTIFIER)
    end
    private_class_method :valid_name?

    # @param value [String]
    # @return [String]
    # @raise [RubySkills::Error]
    def self.parsed_requirement_string(value)
      Gem::Requirement.new(value).to_s
    rescue Gem::Requirement::BadRequirementError
      raise RubySkills::Error, "Invalid version requirement #{value.inspect}"
    end
    private_class_method :parsed_requirement_string
  end
end
