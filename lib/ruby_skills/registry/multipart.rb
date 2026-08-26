# frozen_string_literal: true

require "securerandom"

module RubySkills
  module Registry
    # Builds a +multipart/form-data+ body for publish.
    #
    # @api private
    # @since 0.1.0
    class Multipart
      # @param fields [Hash{String, Symbol => Object}]
      def initialize(fields)
        @fields = fields
        @boundary = "RubySkillsBoundary#{SecureRandom.hex(16)}"
      end

      # @return [String]
      def content_type
        "multipart/form-data; boundary=#{@boundary}"
      end

      # @return [String] binary request body
      def body
        chunks = @fields.flat_map { |name, value| part(name, value) }
        "#{chunks.join}--#{@boundary}--\r\n"
      end

      private

      # @param name [String, Symbol]
      # @param value [Object]
      # @return [Array<String>]
      def part(name, value)
        if file?(value)
          file_part(name, value)
        else
          [text_part(name, value)]
        end
      end

      # @param value [Object]
      # @return [Boolean]
      def file?(value)
        value.is_a?(Hash) && value.key?(:filename) && value.key?(:body)
      end

      # @param name [String, Symbol]
      # @param value [Object]
      # @return [String]
      def text_part(name, value)
        <<~PART.gsub("\n", "\r\n")
          --#{@boundary}
          Content-Disposition: form-data; name="#{name}"

          #{value}
        PART
      end

      # @param name [String, Symbol]
      # @param value [Hash]
      # @return [Array<String>]
      def file_part(name, value)
        filename = value[:filename]
        type = value[:content_type] || "application/octet-stream"
        header = <<~PART.gsub("\n", "\r\n")
          --#{@boundary}
          Content-Disposition: form-data; name="#{name}"; filename="#{filename}"
          Content-Type: #{type}

        PART
        [header, value[:body].to_s.b, "\r\n"]
      end
    end
  end
end
