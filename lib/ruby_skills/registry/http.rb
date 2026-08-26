# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module RubySkills
  module Registry
    # Net::HTTP adapter used by {Client}. Not called from the CLI.
    #
    # @api private
    # @since 0.1.0
    class Http
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 60
      MAX_REDIRECTS = 5

      # @param base_url [String]
      def initialize(base_url:)
        @base_url = base_url.to_s.chomp("/")
      end

      # @param method [Symbol]
      # @param path [String]
      # @param headers [Hash{String => String}]
      # @param json [Hash, nil]
      # @param form [Hash, nil]
      # @return [RubySkills::Registry::Response]
      # @raise [RubySkills::Registry::Error]
      def request(method:, path:, headers: {}, json: nil, form: nil)
        uri = URI.join("#{@base_url}/", path.delete_prefix("/"))
        perform(method, uri, headers: headers, json: json, form: form)
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
             SocketError, OpenSSL::SSL::SSLError => e
        raise Error.new("Could not reach the registry: #{e.message}", code: "network_error")
      end

      private

      # @param method [Symbol]
      # @param uri [URI]
      # @param headers [Hash]
      # @param json [Hash, nil]
      # @param form [Hash, nil]
      # @param redirects [Integer]
      # @return [Response]
      def perform(method, uri, headers:, json:, form:, redirects: 0) # rubocop:disable Metrics/ParameterLists
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = build_request(method, uri, headers: headers, json: json, form: form)
        response = http.request(request)

        if redirect?(response) && method == :get
          return follow_redirect(response, uri, headers: headers, redirects: redirects)
        end

        Response.new(
          status: response.code.to_i,
          headers: header_hash(response),
          body: response.body.to_s.b
        )
      end

      # @param method [Symbol]
      # @param uri [URI]
      # @param headers [Hash]
      # @param json [Hash, nil]
      # @param form [Hash, nil]
      # @return [Net::HTTPRequest]
      def build_request(method, uri, headers:, json:, form:)
        request = http_class(method).new(uri)
        headers.each do |key, value|
          request[key] = value
        end

        if json
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(json)
        elsif form
          multipart = Multipart.new(form)
          request["Content-Type"] = multipart.content_type
          request.body = multipart.body
        end

        request
      end

      # @param method [Symbol]
      # @return [Class]
      def http_class(method)
        case method
        when :get then Net::HTTP::Get
        when :post then Net::HTTP::Post
        when :delete then Net::HTTP::Delete
        else
          raise Error.new("Unsupported HTTP method: #{method}", code: "http_error")
        end
      end

      # @param response [Net::HTTPResponse]
      # @return [Boolean]
      def redirect?(response)
        response.is_a?(Net::HTTPRedirection) && response["location"]
      end

      # @param response [Net::HTTPResponse]
      # @param from [URI]
      # @param headers [Hash]
      # @param redirects [Integer]
      # @return [Response]
      def follow_redirect(response, from, headers:, redirects:)
        if redirects >= MAX_REDIRECTS
          raise Error.new("Too many registry redirects", code: "network_error")
        end

        location = URI.join(from, response["location"])
        unless %w[http https].include?(location.scheme)
          raise Error.new("Refusing non-HTTP redirect", code: "network_error")
        end

        perform(:get, location, headers: headers, json: nil, form: nil, redirects: redirects + 1)
      end

      # @param response [Net::HTTPResponse]
      # @return [Hash{String => String}]
      def header_hash(response)
        headers = {}
        response.each_header do |key, value|
          headers[key.downcase] = value
        end
        headers
      end
    end
  end
end
