# frozen_string_literal: true

module RubySkills
  # Saves a registry API token, either from +--token+ or a browser device login.
  #
  # @example Browser login
  #   RubySkills::Login.new.run { |session| puts session.verification_uri }
  #
  # @since 0.1.0
  class Login
    Result = Struct.new(:status, :verification_uri, :error, keyword_init: true) do
      # @return [Boolean]
      def success?
        status == :logged_in
      end
    end

    # @param token [String, nil]
    # @param client [RubySkills::Registry::Client]
    # @param opener [#call]
    # @param sleeper [#call]
    def initialize(token: nil, client: nil, opener: nil, sleeper: nil)
      @token = token
      @client = client || Registry::Client.new
      @opener = opener || ->(url) { Browser.open(url) }
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    # @yield [session] a {Registry::DeviceLogin} when browser login starts
    # @return [Result]
    def run
      if @token.is_a?(String) && !@token.strip.empty?
        Credentials.load.update_token!(@token)
        return Result.new(status: :logged_in, verification_uri: nil, error: nil)
      end

      session = @client.start_device_authorization
      yield session if block_given?
      @opener.call(session.verification_uri)
      issued = @client.wait_for_device_authorization(session, sleeper: @sleeper)
      Credentials.load.update_token!(issued.token)

      Result.new(status: :logged_in, verification_uri: session.verification_uri, error: nil)
    rescue RubySkills::Error => e
      Result.new(status: :failed, verification_uri: nil, error: e)
    end
  end
end
