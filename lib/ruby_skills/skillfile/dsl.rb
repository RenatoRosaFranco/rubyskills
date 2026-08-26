# frozen_string_literal: true

module RubySkills
  class Skillfile
    # Restricted Skillfile DSL. Only +source+ and +skill+ are defined.
    #
    # @api private
    class Dsl < BasicObject
      # @param skillfile [Skillfile]
      def initialize(skillfile)
        @skillfile = skillfile
      end

      # @param url [String]
      # @return [void]
      def source(url)
        @skillfile.__send__(:declare_source, url, location: current_location)
      end

      # @param name [String]
      # @param requirement [String, nil]
      # @return [void]
      def skill(name, requirement = nil)
        @skillfile.__send__(:declare_skill, name, requirement, location: current_location)
      end

      # @param name [Symbol]
      # @param _args [Array]
      # @return [void]
      def method_missing(name, *_args)
        location = current_location
        ::Kernel.raise Error.new(
          "Unsupported Skillfile method `#{name}`",
          filename: location&.path || @skillfile.path,
          line: location&.lineno
        )
      end

      # @param _name [Symbol]
      # @param _include_private [Boolean]
      # @return [Boolean]
      def respond_to_missing?(_name, _include_private = false)
        false
      end

      private

      # @return [Thread::Backtrace::Location, nil]
      def current_location
        ::Kernel.caller_locations(2, 1)&.first
      end
    end
  end
end
