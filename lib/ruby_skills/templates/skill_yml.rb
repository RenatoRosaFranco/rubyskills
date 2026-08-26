# frozen_string_literal: true

module RubySkills
  module Templates
    # Renders the starter +skill.yml+ for a new skill.
    #
    # @since 0.1.0
    class SkillYml
      # @param namespace [String]
      # @param name [String]
      def initialize(namespace:, name:)
        @namespace = namespace
        @name = name
      end

      # @return [String]
      def render
        <<~YAML
          name: #{@name}
          namespace: #{@namespace}
          version: 0.1.0

          summary: TODO

          categories: []

          tags: []

          entrypoint: SKILL.md

          compatibility: {}

          files:
            - SKILL.md
            - references/**
        YAML
      end
    end
  end
end
