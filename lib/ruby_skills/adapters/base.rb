# frozen_string_literal: true

module RubySkills
  # Agent-specific mirrors of canonical +.ruby-skills+ storage.
  #
  # {Adapters.all} lists Claude, Codex, Cursor, and VS Code. Commands update
  # canonical storage first, then call {Adapters.sync_remove}.
  module Adapters
    class << self
      # Adapter classes that mirror canonical storage into agent directories.
      #
      # @return [Array<Class>]
      def all
        [Claude, Codex, Cursor, Vscode]
      end

      # Remove +name+ from every adapter destination under +root+.
      #
      # @param name [String]
      # @param root [String, Pathname]
      # @return [void]
      def sync_remove(name, root:)
        all.each do |klass|
          klass.new(root: root).remove(name)
        end
      end
    end

    # Base implementation for skill adapters.
    #
    # Subclasses must define an ADAPTER_INFO constant containing:
    #
    # - :adapter   — tool directory under the project root
    # - :directory — directory containing skills
    #
    # @abstract
    # @since 0.1.0
    class Base
      # @param root [String, Pathname] project root
      def initialize(root: Dir.pwd)
        @root = Pathname.new(root)
      end

      # Install a skill into the adapter destination.
      #
      # @param name [String] skill identifier
      # @param source [String, Pathname] source skill path
      # @return [void]
      def install(name, source)
        link(source, destination_for(name))
      end

      # Remove an installed skill.
      #
      # @param name [String] skill identifier
      # @return [void]
      def remove(name)
        FileUtils.rm_rf(destination_for(name))
      end

      private

      attr_reader :root

      # @return [Hash{Symbol => String}]
      def adapter_info
        self.class::ADAPTER_INFO
      end

      # @param name [String]
      # @return [Pathname]
      def destination_for(name)
        root.join(
          adapter_info.fetch(:adapter),
          adapter_info.fetch(:directory),
          name
        )
      end
    end
  end
end
