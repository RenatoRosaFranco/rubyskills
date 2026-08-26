# frozen_string_literal: true

require "pathname"
require "rubygems"
require "uri"

module RubySkills
  # Exact resolved state for a project's {Skillfile}.
  #
  # The Skillfile is declared intent. Skills.lock is the reproducible
  # record of versions and artifact checksums. Parsing and writing do not
  # talk to the network.
  #
  # @example
  #   lockfile = RubySkills::Lockfile.load("Skills.lock")
  #   lockfile.find("rails/conventions").version
  #
  # @since 0.1.0
  class Lockfile
    # Filename of the project lockfile.
    FILENAME = "Skills.lock"

    class << self
      # @param path [String, Pathname]
      # @return [Lockfile]
      # @raise [Error]
      def load(path)
        file = Pathname.new(path)
        raise Error.new("Skills.lock not found", filename: file) unless file.file?

        Parser.new(file).parse
      rescue Error
        raise
      rescue SystemCallError, ArgumentError => e
        raise Error.new("Malformed Skills.lock: #{e.message}", filename: file)
      end

      # @param url [String]
      # @param filename [String, Pathname, nil]
      # @param line [Integer, nil]
      # @return [String]
      # @raise [Error]
      def normalize_source(url, filename: nil, line: nil)
        raw = url.to_s.strip.chomp("/")
        uri = URI.parse(raw)
        return raw if uri.is_a?(URI::HTTP) && uri.host

        raise Error.new("Invalid source #{url.inspect}", filename: filename, line: line)
      rescue URI::InvalidURIError
        raise Error.new("Invalid source #{url.inspect}", filename: filename, line: line)
      end
    end

    # @return [Pathname, nil]
    attr_reader :path

    # @return [String]
    attr_reader :source

    # @return [Array<LockedSkill>]
    attr_reader :skills

    # @return [Array<Dependency>]
    attr_reader :dependencies

    # @param source [String]
    # @param skills [Array<LockedSkill>]
    # @param dependencies [Array<Dependency>]
    # @param path [String, Pathname, nil]
    def initialize(source:, skills: [], dependencies: [], path: nil)
      @source = self.class.normalize_source(source)
      @skills = skills.sort_by(&:name).freeze
      @dependencies = dependencies.sort_by(&:name).freeze
      @path = path && Pathname.new(path)
    end

    # @param name [String]
    # @return [LockedSkill, nil]
    def find(name)
      @skills.find { |skill| skill.name == name }
    end

    # @param name [String]
    # @return [Boolean]
    def locked?(name)
      !find(name).nil?
    end

    # Whether +dependency+'s requirement is satisfied by the locked version.
    #
    # @param dependency [Dependency]
    # @return [Boolean]
    def satisfies?(dependency)
      locked = find(dependency.name)
      return false unless locked

      dependency.requirement.satisfied_by?(locked.version)
    end

    # True when the lock no longer matches the Skillfile's declared intent.
    #
    # @param skillfile [Skillfile]
    # @return [Boolean]
    def stale_against?(skillfile)
      wanted = skillfile.dependencies.map(&:name)
      locked = @skills.map(&:name)
      declared = @dependencies.map(&:name)

      return true if wanted.sort != locked.sort
      return true if wanted.sort != declared.sort

      skillfile.dependencies.any? { |dependency| !satisfies?(dependency) }
    end

    # Write a byte-identical lockfile for this resolved state.
    #
    # @param path [String, Pathname]
    # @return [void]
    def write(path)
      destination = Pathname.new(path)
      AtomicFile.write(destination, serialize)
      @path = destination
    end

    # @return [String]
    def serialize
      Serializer.new(self).to_s
    end
  end
end
