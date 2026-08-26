# frozen_string_literal: true

module RubySkills
  module Templates
    # Renders the starter +SKILL.md+ for a new skill.
    #
    # @since 0.1.0
    class SkillMd
      # @param namespace [String]
      # @param name [String]
      def initialize(namespace:, name:)
        @namespace = namespace
        @name = name
      end

      # @return [String]
      def render
        <<~MARKDOWN
          # #{title}

          ## Purpose

          Describe what this skill teaches the agent.

          ## Guidance

          Add the Ruby/Rails engineering knowledge here.
        MARKDOWN
      end

      private

      # @api private
      # @return [String]
      def title
        [@namespace, @name].map { |part| humanize(part) }.join(" ")
      end

      # @api private
      # @param value [String]
      # @return [String]
      def humanize(value)
        value.split(/[-_]/).map(&:capitalize).join(" ")
      end
    end
  end
end
