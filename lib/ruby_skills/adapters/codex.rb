# frozen_string_literal: true

module RubySkills
  module Adapters
    # Exposes skills to Codex under +.codex/skills+.
    #
    # @see RubySkills::Adapters::Base
    # @since 0.1.0
    class Codex < Base
      # Path fragments that locate Codex skills.
      #
      # @return [Hash{Symbol => String}]
      ADAPTER_INFO = {
        adapter: ".codex",
        directory: "skills"
      }.freeze
    end
  end
end
