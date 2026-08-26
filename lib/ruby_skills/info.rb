# frozen_string_literal: true

module RubySkills
  # Read-only registry lookup for +ruby-skills info+.
  #
  # Does not install files or mutate the project.
  #
  # @example
  #   result = RubySkills::Info.new("rails/request-specs").run
  #   result.skill.latest_version
  #
  # @since 0.1.0
  class Info
    Result = Struct.new(:skill, :error, keyword_init: true) do
      # @return [Boolean]
      def success?
        error.nil? && skill
      end
    end

    # @param name [String] +namespace/skill+
    # @param client [RubySkills::Registry::Client]
    def initialize(name, client: nil)
      @name = name
      @client = client || Registry::Client.new
    end

    # @return [Result]
    def run
      Result.new(skill: @client.get_skill(@name), error: nil)
    rescue Registry::Error => e
      Result.new(skill: nil, error: e)
    end
  end
end
