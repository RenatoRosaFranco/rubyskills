# frozen_string_literal: true

module RubySkills
  # Read-only lookup of the logged-in registry user for +ruby-skills whoami+.
  #
  # @example
  #   result = RubySkills::Whoami.new.run
  #   result.user.email
  #
  # @since 0.1.0
  class Whoami
    Result = Struct.new(:status, :user, :error, keyword_init: true) do
      # @return [Boolean]
      def success?
        status == :ok && user
      end
    end

    # @param client [RubySkills::Registry::Client]
    def initialize(client: nil)
      @client = client || Registry::Client.new
    end

    # @return [Result]
    def run
      return unauthenticated if @client.token.to_s.empty?

      Result.new(status: :ok, user: @client.current_user, error: nil)
    rescue Registry::Error => e
      return unauthenticated(e) if e.code == "unauthenticated" || e.status == 401

      Result.new(status: :failed, user: nil, error: e)
    end

    private

    # @param error [RubySkills::Registry::Error, nil]
    # @return [Result]
    def unauthenticated(error = nil)
      Result.new(status: :unauthenticated, user: nil, error: error)
    end
  end
end
