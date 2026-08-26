# frozen_string_literal: true

module RubySkills
  class Outdated
    # Renders {Outdated::Result} as a fixed-width table.
    #
    # @api private
    class Report
      HEADERS = %w[Skill Current Allowed Latest Status].freeze

      # @param result [Result]
      def initialize(result)
        @result = result
      end

      # @return [String] always ends with a newline when there is output
      def to_s
        rows = [HEADERS] + @result.rows.map { |row|
          [row.name, row.current_label, row.allowed_label, row.latest_label, row.human_status]
        }
        widths = HEADERS.each_index.map { |index| rows.map { |row| row[index].length }.max }

        "#{rows.map { |row|
          row.each_index.map { |index| row[index].ljust(widths[index]) }.join("  ").rstrip
        }.join("\n")}\n"
      end
    end
  end
end
