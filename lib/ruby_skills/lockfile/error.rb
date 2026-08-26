# frozen_string_literal: true

module RubySkills
  class Lockfile
    # Raised when a Skills.lock is missing or malformed.
    class Error < RubySkills::Error
      # @return [String, nil]
      attr_reader :filename

      # @return [Integer, nil]
      attr_reader :line

      # @param message [String]
      # @param filename [String, Pathname, nil]
      # @param line [Integer, nil]
      def initialize(message, filename: nil, line: nil)
        @filename = filename&.to_s
        @line = line
        super(located_message(message))
      end

      private

      # @param message [String]
      # @return [String]
      def located_message(message)
        return message if @filename.nil?

        prefix = @line ? "#{@filename}:#{@line}" : @filename
        "#{prefix}: #{message}"
      end
    end
  end
end
