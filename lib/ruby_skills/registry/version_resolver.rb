# frozen_string_literal: true

require "rubygems"

module RubySkills
  module Registry
    # Picks the highest available version that satisfies a RubyGems requirement.
    #
    # Operates on version strings from {Client#get_skill} (+versions+ already
    # omits yanked and unpublished releases). Does not talk to the network.
    #
    # @api private
    # @since 0.1.0
    class VersionResolver
      # @param versions [Array<String>]
      # @param requirement [String, Array, Gem::Requirement]
      def initialize(versions, requirement)
        @versions = versions
        @requirement = requirement
      end

      # @return [String, nil]
      def resolve
        matches = compatible
        return if matches.empty?

        matches.max_by { |version| Gem::Version.new(version) }
      end

      private

      # @return [Array<String>]
      def compatible
        parsed = compile_requirement
        return [] if parsed.nil?

        numbered = @versions.select { |version| Gem::Version.correct?(version) }
        return numbered if parsed == :latest

        numbered.select { |version| parsed.satisfied_by?(Gem::Version.new(version)) }
      end

      # @return [Gem::Requirement, :latest, nil]
      def compile_requirement
        case @requirement
        when Gem::Requirement
          @requirement
        when Array
          Gem::Requirement.create(@requirement)
        else
          raw = @requirement.to_s.strip
          return if raw.empty?
          return :latest if raw.casecmp("latest").zero?

          Gem::Requirement.create(raw)
        end
      rescue ArgumentError
        nil
      end
    end
  end
end
