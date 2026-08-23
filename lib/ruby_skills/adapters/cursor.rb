# frozen_string_literal: true

module RubySkills
  module Adapters
    # Exposes skills to Cursor under +.cursor/skills+.
    #
    # @see RubySkills::Adapters::Base
    # @since 0.1.0
    class Cursor < Base
      # Path fragments that locate Cursor skills.
      #
      # @return [Hash{Symbol => String}]
      ADAPTER_INFO = {
        adapter: ".cursor",
        directory: "skills"
      }.freeze
    end
  end
end
