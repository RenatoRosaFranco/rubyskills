# frozen_string_literal: true

module RubySkills
  module Adapters
    # Exposes skills to VS Code under +.vscode/skills+.
    #
    # @see RubySkills::Adapters::Base
    # @since 0.1.0
    class Vscode < Base
      # Path fragments that locate VS Code skills.
      #
      # @return [Hash{Symbol => String}]
      ADAPTER_INFO = {
        adapter: ".vscode",
        directory: "skills"
      }.freeze
    end
  end
end
