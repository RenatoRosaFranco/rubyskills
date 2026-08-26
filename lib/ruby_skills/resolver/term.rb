# frozen_string_literal: true

module RubySkills
  class Resolver
    # A single requirement on a skill, with the parent that introduced it.
    #
    # +parent_name+ is +nil+ when the term comes from the Skillfile.
    class Term
      # @return [String]
      attr_reader :name

      # @return [Gem::Requirement]
      attr_reader :requirement

      # @return [String, nil]
      attr_reader :parent_name

      # @param name [String]
      # @param requirement [Gem::Requirement, String]
      # @param parent_name [String, nil]
      def initialize(name:, requirement:, parent_name: nil)
        @name = name
        @requirement = if requirement.is_a?(Gem::Requirement)
                         requirement
                       else
                         Gem::Requirement.new(requirement)
                       end
        @parent_name = parent_name
      end

      # @return [Boolean]
      def from_skillfile?
        @parent_name.nil?
      end

      # @return [String]
      def source_label
        @parent_name || "Skillfile"
      end
    end
  end
end
