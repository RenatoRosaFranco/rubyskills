# frozen_string_literal: true

require "pathname"
require "rubygems"
require "uri"

module RubySkills
  class Lockfile
    # Line-oriented parser for the Bundler-style Skills.lock format.
    #
    # @api private
    class Parser # rubocop:disable Metrics/ClassLength
      HEADER = "RUBY SKILLS"
      DEPENDENCIES = "DEPENDENCIES"
      SKILL_LINE = %r{\A  ([a-z0-9_-]+/[a-z0-9_-]+) \((.+)\)\z}
      CHECKSUM_LINE = /\A    sha256:\s*(.+)\z/
      REMOTE_LINE = /\A  remote:\s*(.+)\z/
      DEPENDENCY_LINE = %r{\A  ([a-z0-9_-]+/[a-z0-9_-]+)(?: \((.+)\))?\z}
      CHECKSUM_HEX = /\A[0-9a-f]{64}\z/i

      # @param path [Pathname]
      def initialize(path)
        @path = Pathname.new(path)
        @lines = @path.read.lines.map.with_index(1) { |line, number|
          [number, line.chomp.chomp("\r")]
        }
        @index = 0
      end

      # @return [Lockfile]
      def parse
        expect_header!
        source = read_remote!
        skills = read_skills!
        dependencies = read_dependencies!

        Lockfile.new(source: source, skills: skills, dependencies: dependencies, path: @path)
      end

      private

      # @return [void]
      def expect_header!
        skip_blanks
        number, text = read_line
        return if text == HEADER

        raise_at(number, "Malformed section #{text.inspect}")
      end

      # @return [String]
      def read_remote!
        skip_blanks
        number, text = peek || raise_at(nil, "Invalid source")
        match = REMOTE_LINE.match(text)
        raise_at(number, "Invalid source") unless match

        @index += 1
        Lockfile.normalize_source(match[1], filename: @path, line: number)
      end

      # @return [Array<LockedSkill>]
      def read_skills!
        skills = []
        seen = {}

        loop do
          skip_blanks
          break if peek_text == DEPENDENCIES || peek.nil?

          skills << read_skill(seen)
        end

        skills
      end

      # @param seen [Hash{String => true}]
      # @return [LockedSkill]
      def read_skill(seen)
        number, text = read_line
        match = SKILL_LINE.match(text)
        raise_at(number, "Malformed section #{text.inspect}") unless match

        name = match[1]
        raise_at(number, "Duplicated locked skill #{name.inspect}") if seen[name]
        seen[name] = true
        version = parse_version(match[2], number)
        checksum = read_checksum!(name, number)

        LockedSkill.new(name: name, version: version, checksum: checksum)
      end

      # @param name [String]
      # @param skill_line [Integer]
      # @return [String]
      def read_checksum!(name, skill_line)
        skip_blanks
        number, text = peek
        raise_at(skill_line, "Missing checksum for #{name}") if number.nil? || text == DEPENDENCIES

        match = CHECKSUM_LINE.match(text.to_s)
        raise_at(number, "Missing checksum for #{name}") unless match

        @index += 1
        hex = match[1].to_s.strip.delete_prefix("sha256:").downcase
        raise_at(number, "Malformed checksum #{match[1].inspect}") unless hex.match?(CHECKSUM_HEX)

        "sha256:#{hex}"
      end

      # @return [Array<Dependency>]
      def read_dependencies!
        skip_blanks
        number, text = read_line
        raise_at(number || nil, "Malformed section") unless text == DEPENDENCIES

        dependencies = []
        seen = {}
        loop do
          skip_blanks
          break if peek.nil?

          dependencies << read_dependency(seen)
        end
        dependencies
      end

      # @param seen [Hash{String => true}]
      # @return [Dependency]
      def read_dependency(seen)
        number, text = read_line
        match = DEPENDENCY_LINE.match(text)
        raise_at(number, "Malformed dependency #{text.inspect}") unless match

        name = match[1]
        raise_at(number, "Duplicated dependency #{name.inspect}") if seen[name]
        seen[name] = true

        requirement = parse_requirement(name, match[2], number)
        Dependency.new(name: name, requirement: requirement)
      end

      # @param value [String]
      # @param line [Integer]
      # @return [Gem::Version]
      def parse_version(value, line)
        raise_at(line, "Invalid version #{value.inspect}") unless Gem::Version.correct?(value)

        Gem::Version.new(value)
      end

      # @param name [String]
      # @param value [String, nil]
      # @param line [Integer]
      # @return [Gem::Requirement]
      def parse_requirement(name, value, line)
        return Gem::Requirement.default if value.nil? || value.strip.empty?

        Gem::Requirement.new(value)
      rescue Gem::Requirement::BadRequirementError
        raise_at(line, "Malformed dependency #{name} (#{value})")
      end

      # @return [void]
      def skip_blanks
        @index += 1 while peek && peek_text.empty?
      end

      # @return [Array(Integer, String), nil]
      def peek
        @lines[@index]
      end

      # @return [String, nil]
      def peek_text
        peek&.last
      end

      # @return [Array(Integer, String)]
      def read_line
        entry = @lines[@index]
        raise_at(nil, "Malformed section") unless entry

        @index += 1
        entry
      end

      # @param line [Integer, nil]
      # @param message [String]
      # @return [void]
      def raise_at(line, message)
        raise Error.new(message, filename: @path, line: line)
      end
    end
  end
end
