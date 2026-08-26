# frozen_string_literal: true

require "pathname"
require "rubygems"

module RubySkills
  # Project-level declared intent: registry origin and skill dependencies.
  #
  # Parsing evaluates a small Ruby DSL inside a restricted context. It does
  # not talk to the network or install anything.
  #
  # @example
  #   skillfile = RubySkills::Skillfile.load("Skillfile")
  #   skillfile.find("rails/request-specs").requirement
  #
  # @since 0.1.0
  class Skillfile # rubocop:disable Metrics/ClassLength
    # Filename searched by {Skillfile.find}.
    FILENAME = "Skillfile"

    class << self
      # Load and parse a Skillfile from an explicit path.
      #
      # @param path [String, Pathname]
      # @param default_source [String, nil] overrides the configured registry
      # @return [Skillfile]
      # @raise [Error]
      def load(path, default_source: nil)
        file = Pathname.new(path)
        raise missing_error(file) unless file.file?

        parse(file, default_source: default_source)
      end

      # Walk from +starting_directory+ toward the filesystem root until a
      # Skillfile is found.
      #
      # @param starting_directory [String, Pathname]
      # @param default_source [String, nil]
      # @return [Skillfile]
      # @raise [Error] if no Skillfile exists in that ancestry
      def find(starting_directory = Dir.pwd, default_source: nil)
        start = Pathname.new(starting_directory).expand_path
        dir = start.directory? ? start : start.dirname

        loop do
          candidate = dir.join(FILENAME)
          return load(candidate, default_source: default_source) if candidate.file?

          parent = dir.parent
          break if parent == dir

          dir = parent
        end

        raise Error.new(
          "Skillfile not found (searched from #{start})",
          filename: start.join(FILENAME)
        )
      end

      private

      # @param path [Pathname]
      # @param default_source [String, nil]
      # @return [Skillfile]
      def parse(path, default_source:)
        skillfile = new(
          path: path,
          source: default_source || configured_registry,
          dependencies: []
        )
        Dsl.new(skillfile).instance_eval(path.read, path.to_s, 1)
        skillfile
      rescue Error
        raise
      rescue SyntaxError, NameError, ArgumentError, TypeError => e
        raise Error.new("Malformed Skillfile: #{e.message}", filename: path)
      end

      # @return [String]
      def configured_registry
        env = ENV.fetch(Registry::URL_ENV, "").to_s.strip
        return env.chomp("/") unless env.empty?

        UserConfig.load.registry
      end

      # @param path [Pathname]
      # @return [Error]
      def missing_error(path)
        Error.new("Skillfile not found", filename: path)
      end
    end

    # @return [Pathname]
    attr_reader :path

    # @return [String]
    attr_reader :source

    # @return [Array<Dependency>]
    attr_reader :dependencies

    # @param path [Pathname]
    # @param source [String]
    # @param dependencies [Array<Dependency>]
    def initialize(path:, source:, dependencies:)
      @path = Pathname.new(path)
      @source = source
      @dependencies = dependencies
      @source_declared = false
    end

    # @param name [String]
    # @return [Dependency, nil]
    def find(name)
      @dependencies.find { |dependency| dependency.name == name }
    end

    # @param name [String]
    # @return [Boolean]
    def include?(name)
      !find(name).nil?
    end

    # @return [Hash]
    def to_h
      {
        source: @source,
        dependencies: @dependencies.map do |dependency|
          { name: dependency.name, requirement: dependency.requirement.to_s }
        end
      }
    end

    private

    # @param url [String]
    # @param location [Thread::Backtrace::Location, nil]
    # @return [void]
    def declare_source(url, location:)
      raise_at(location, "Duplicated source declaration") if @source_declared

      raw = url.to_s.strip
      raise_at(location, "Invalid source #{url.inspect}") if raw.empty?

      @source = raw.chomp("/")
      @source_declared = true
    end

    # @param name [Object]
    # @param requirement [Object]
    # @param location [Thread::Backtrace::Location, nil]
    # @return [void]
    def declare_skill(name, requirement, location:)
      identifier = name.to_s.strip
      raise_at(location, "Invalid skill identifier #{name.inspect}") unless valid_name?(identifier)
      raise_at(location, "Duplicated skill #{identifier.inspect}") if include?(identifier)

      @dependencies << Dependency.new(
        name: identifier,
        requirement: parse_requirement(identifier, requirement, location: location)
      )
    end

    # @param name [String]
    # @return [Boolean]
    def valid_name?(name)
      namespace, skill, extra = name.split("/", 3)
      extra.nil? &&
        namespace.to_s.match?(Manifest::IDENTIFIER) &&
        skill.to_s.match?(Manifest::IDENTIFIER)
    end

    # @param name [String]
    # @param requirement [Object]
    # @param location [Thread::Backtrace::Location, nil]
    # @return [Gem::Requirement]
    def parse_requirement(name, requirement, location:)
      return Gem::Requirement.default if requirement.nil? || requirement.to_s.strip.empty?

      Gem::Requirement.new(requirement)
    rescue Gem::Requirement::BadRequirementError
      raise_at(
        location,
        "Invalid version requirement #{requirement.inspect} for #{name}"
      )
    end

    # @param location [Thread::Backtrace::Location, nil]
    # @param message [String]
    # @return [void]
    def raise_at(location, message)
      raise Error.new(
        message,
        filename: location&.path || @path,
        line: location&.lineno
      )
    end
  end
end
