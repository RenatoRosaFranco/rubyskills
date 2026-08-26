# frozen_string_literal: true

module RubySkills
  class Resolver
    # Base error for a failed resolve. Nothing is written to disk.
    class ResolutionError < RubySkills::Error; end

    # Historical alias used by install/update callers.
    Error = ResolutionError

    # No published version satisfies the intersection of requirements.
    class VersionConflict < ResolutionError
      # @return [String]
      attr_reader :skill_name

      # @return [Array<Term>]
      attr_reader :terms

      # @param skill_name [String]
      # @param terms [Array<Term>]
      def initialize(skill_name, terms)
        @skill_name = skill_name
        @terms = Array(terms)
        super(conflict_message)
      end

      private

      # @return [String]
      def conflict_message
        lines = @terms.sort_by { |term| [term.source_label, term.requirement.to_s] }.map { |term|
          "#{term.source_label} -> #{@skill_name} (#{term.requirement})"
        }

        <<~MSG.chomp
          Unable to resolve #{@skill_name}.

          Requirements:
          #{lines.join("\n")}

          No published version satisfies all requirements.
        MSG
      end
    end

    # A depends on B depends on A.
    class CircularDependency < ResolutionError
      # @return [Array<String>]
      attr_reader :cycle

      # @param cycle [Array<String>]
      def initialize(cycle)
        @cycle = Array(cycle)
        super("Circular dependency: #{@cycle.join(" -> ")}")
      end
    end

    # The registry has no such skill.
    class SkillNotFound < ResolutionError; end

    # A single requirement matches no published release.
    class NoCompatibleVersion < ResolutionError; end
  end
end
