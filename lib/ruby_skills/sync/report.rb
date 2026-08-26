# frozen_string_literal: true

module RubySkills
  class Sync
    # Stdout reporter for {Sync}.
    #
    # @api private
    class Report
      # @param io [#puts]
      def initialize(io)
        @io = io
      end

      # @param result [Result]
      # @param adapters [Array<Adapters::Base>]
      # @return [void]
      def print(result, adapters:)
        if result.dry_run
          print_dry_run(result, adapters)
        else
          print_applied(result, adapters)
        end
      end

      private

      # @param result [Result]
      # @param adapters [Array<Adapters::Base>]
      # @return [void]
      def print_applied(result, adapters)
        @io.puts "Synchronizing Ruby Skills..."
        @io.puts
        adapters.each_with_index do |adapter, index|
          print_agent(adapter, result.changes[index])
          @io.puts
        end
        @io.puts summary(result)
      end

      # @param result [Result]
      # @param adapters [Array<Adapters::Base>]
      # @return [void]
      def print_dry_run(result, adapters)
        if unavailable_only?(result)
          adapters.each_with_index do |adapter, index|
            print_agent(adapter, result.changes[index])
            @io.puts
          end
          return
        end

        added = labeled_changes(adapters, result.changes, :added)
        removed = labeled_changes(adapters, result.changes, :removed)
        if added.empty? && removed.empty?
          @io.puts "Nothing to change."
          return
        end

        print_would("Would add:", added)
        print_would("Would remove:", removed)
      end

      # @param title [String]
      # @param rows [Array<String>]
      # @return [void]
      def print_would(title, rows)
        return if rows.empty?

        @io.puts title
        rows.each do |row|
          @io.puts "  #{row}"
        end
        @io.puts
      end

      # @param adapters [Array<Adapters::Base>]
      # @param changes [Array<Adapters::ChangeSet>]
      # @param field [Symbol]
      # @return [Array<String>]
      def labeled_changes(adapters, changes, field)
        rows = []
        adapters.each_with_index do |adapter, index|
          changeset = changes[index]
          next unless changeset.available

          changeset.public_send(field).each do |label|
            rows << "#{adapter.name}: #{label}"
          end
        end
        rows
      end

      # @param adapter [Adapters::Base]
      # @param changeset [Adapters::ChangeSet]
      # @return [void]
      def print_agent(adapter, changeset)
        @io.puts adapter.name
        unless changeset.available
          @io.puts "  not detected"
          return
        end

        if changeset.current.empty?
          @io.puts "  (none)"
          return
        end

        changeset.current.each do |label|
          @io.puts "  ✓ #{label}"
        end
      end

      # @param result [Result]
      # @return [String]
      def summary(result)
        skills = noun(result.skill_count, "skill", "skills")
        agents = noun(result.agent_count, "agent", "agents")
        "Synced #{result.skill_count} #{skills} to #{result.agent_count} #{agents}."
      end

      # @param count [Integer]
      # @param singular [String]
      # @param plural [String]
      # @return [String]
      def noun(count, singular, plural)
        count == 1 ? singular : plural
      end

      # @param result [Result]
      # @return [Boolean]
      def unavailable_only?(result)
        result.changes.any? && result.changes.none?(&:available)
      end
    end
  end
end
