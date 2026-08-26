# frozen_string_literal: true

module RubySkills
  class Updater
    # Stdout reporter for {Updater}.
    #
    # @api private
    class Report
      # @param io [#puts]
      def initialize(io)
        @io = io
      end

      # @param name [String]
      # @return [void]
      def updating(name)
        @io.puts "Updating #{name}..."
        @io.puts
      end

      # @param from [Gem::Version, String]
      # @param to [Gem::Version, String]
      # @return [void]
      def bump(from, to)
        @io.puts "#{from} -> #{to}"
        @io.puts
      end

      # @return [void]
      def downloaded
        @io.puts "✓ downloaded"
      end

      # @return [void]
      def checksum_verified
        @io.puts "✓ checksum verified"
      end

      # @return [void]
      def installed
        @io.puts "✓ installed"
      end

      # @return [void]
      def lock_updated
        @io.puts "✓ Skills.lock updated"
      end

      # @param name [String]
      # @return [void]
      def already_current(name)
        @io.puts "#{name} is already at the newest compatible version."
      end

      # @return [void]
      def all_current
        @io.puts "All skills are already at the newest compatible versions."
      end
    end
  end
end
