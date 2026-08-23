# frozen_string_literal: true

module RubySkills
  module Adapters
    # Exposes skills to Claude Code under +.claude/skills+.
    #
    # @see RubySkills::Adapters::Base
    # @since 0.1.0
    class Claude < Base
      # Path fragments that locate Claude skills.
      #
      # @return [Hash{Symbol => String}]
      ADAPTER_INFO = {
        adapter: ".claude",
        directory: "skills"
      }.freeze
    end
  end
end
