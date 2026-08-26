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

      body = stub[:body]
      body = JSON.generate(body) unless body.is_a?(String)

      RubySkills::Registry::Response.new(
        status: stub[:status],
        headers: stub[:headers].transform_keys(&:to_s).transform_keys(&:downcase),
        body: body.to_s.b
      )
    end
  end
end
