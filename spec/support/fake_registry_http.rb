# frozen_string_literal: true

require "json"

module RubySkillsSpec
  # In-memory HTTP double for {RubySkills::Registry::Client} specs.
  class FakeRegistryHttp
    Request = Struct.new(:http_method, :path, :headers, :json, :form, keyword_init: true)

    # @return [Array<Request>]
    attr_reader :requests

    def initialize
      @requests = []
      @stubs = []
    end

    # @param method [Symbol]
    # @param path [String]
    # @param status [Integer]
    # @param body [String, Hash, Array]
    # @param headers [Hash{String => String}]
    # @return [self]
    def stub(method, path, status:, body: "", headers: {})
      @stubs << {
        method: method.to_sym,
        path: path,
        status: status,
        body: body,
        headers: headers
      }
      self
    end

    # @param method [Symbol]
    # @param path [String]
    # @param headers [Hash]
    # @param json [Hash, nil]
    # @param form [Hash, nil]
    # @return [RubySkills::Registry::Response]
    def request(method:, path:, headers: {}, json: nil, form: nil)
      @requests << Request.new(
        http_method: method.to_sym,
        path: path,
        headers: headers,
        json: json,
        form: form
      )

      stub = @stubs.find { |entry| entry[:method] == method.to_sym && entry[:path] == path }
      raise "unstubbed #{method.upcase} #{path}" unless stub

      status, headers, body = resolve_stub(stub)
      body = JSON.generate(body) unless body.is_a?(String)

      RubySkills::Registry::Response.new(
        status: status,
        headers: headers.transform_keys(&:to_s).transform_keys(&:downcase),
        body: body.to_s.b
      )
    end

    # First poll is pending; the next poll issues +issued+.
    #
    # @param issued [String]
    # @param uri [String]
    # @return [self]
    def stub_device_login(issued:, uri: "https://rubyskills.org/cli/authorize/abc")
      polls = 0
      stub(
        :post,
        "/api/v1/auth/device",
        status: 200,
        body: {
          "device_code" => "device-secret",
          "verification_uri" => uri,
          "expires_in" => 600,
          "interval" => 0
        }
      )
      stub(
        :post,
        "/api/v1/auth/device/token",
        status: 400,
        body: lambda {
          polls += 1
          if polls == 1
            {
              status: 400,
              body: {
                "error" => {
                  "code" => "authorization_pending",
                  "message" => "Authorization pending"
                }
              }
            }
          else
            { status: 201, body: { "token" => issued, "token_type" => "Bearer" } }
          end
        }
      )
      self
    end

    private

    # @param stub [Hash]
    # @return [Array(Integer, Hash, Object)]
    def resolve_stub(stub)
      body = stub[:body]
      status = stub[:status]
      headers = stub[:headers]
      return [status, headers, body] unless body.respond_to?(:call)

      payload = body.call
      if payload.is_a?(Hash) && payload.key?(:status)
        [payload[:status], payload.fetch(:headers, headers), payload[:body]]
      else
        [status, headers, payload]
      end
    end
  end
end
