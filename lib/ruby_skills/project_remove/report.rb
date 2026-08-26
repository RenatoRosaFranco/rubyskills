# frozen_string_literal: true

module RubySkills
  class ProjectRemove
    # Stdout reporter for {ProjectRemove}.
    #
    # @api private
    class Report
      # @param io [#puts]
      def initialize(io)
        @io = io
      end

      # @param name [String]
      # @return [void]
      def removing(name)
        @io.puts "Removing #{name} from project..."
        @io.puts
      end

      # @return [void]
      def skillfile_updated
        @io.puts "✓ Skillfile updated"
      end

      # @param artifact [RemovalPlanner::Artifact]
      # @return [void]
      def removed_artifact(artifact)
        @io.puts "✓ #{artifact.name} #{artifact.version} removed"
      end

      # @return [void]
      def no_artifact
        @io.puts "- no installed artifact to remove"
      end

      # @return [void]
      def lock_updated
        @io.puts "✓ Skills.lock updated"
      end

      # @param name [String]
      # @return [void]
      def done(name)
        @io.puts
        @io.puts "Removed #{name}."
      end

      # @param error [Exception]
      # @return [void]
      def adapter_failed(error)
        @io.puts
        @io.puts "Warning: adapter sync failed: #{error.message}"
      end
    end
  end
end
