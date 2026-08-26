# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "uri"

module RubySkills
  module Registry
    # HTTP client for the Ruby Skills registry.
    #
    # Application services (install, publish, search) call this object. The
    # CLI never uses +Net::HTTP+ or Faraday.
    #
    # @example
    #   client = RubySkills::Registry::Client.new
    #   client.authenticate(email: "dev@example.com", password: "secret")
    #   skill = client.get_skill("rails/request-specs")
    #   version = client.resolve_version("rails/request-specs", "~> 0.1")
    #
    # @since 0.1.0
    class Client # rubocop:disable Metrics/ClassLength
      USER_AGENT_FORMAT = "ruby-skills/%s"
      CHECKSUM_HEADER = "x-ruby-skills-sha256"

      # @return [String]
      attr_reader :base_url

      # @return [String, nil]
      attr_accessor :token

      # @param base_url [String]
      # @param token [String, nil]
      # @param http [#request] injectable transport; defaults to {Http}
      def initialize(base_url: default_base_url, token: default_token, http: nil)
        @base_url = base_url.to_s.chomp("/")
        @token = token
        @http = http || Http.new(base_url: @base_url)
      end

      # Issue an API token and store it on this client.
      #
      # @param email [String]
      # @param password [String]
      # @param otp_code [String, nil]
      # @return [Token]
      # @raise [Error]
      def authenticate(email:, password:, otp_code: nil)
        payload = { email: email, password: password }
        payload[:otp_code] = otp_code unless otp_code.to_s.empty?

        data = json_body(request(:post, "/api/v1/auth/token", json: payload))
        @token = data.fetch("token")
        Token.new(token: @token, token_type: data["token_type"] || "Bearer")
      end

      # Publish a +.rskill+ artifact. Requires {#token}.
      #
      # @param name [String] +namespace/skill+
      # @param version [String]
      # @param checksum [String] SHA-256 of the artifact bytes
      # @param manifest [Hash, String] JSON object or encoded JSON
      # @param artifact [String, Pathname] path to the +.rskill+
      # @return [PublishedVersion]
      # @raise [Error]
      def publish_version(name:, version:, checksum:, manifest:, artifact:)
        require_token!
        namespace, skill = split_name(name)
        filename, bytes = read_artifact(artifact)

        data = json_body(
          request(
            :post,
            skill_path(namespace, skill, "versions"),
            form: {
              version: version,
              checksum: checksum,
              manifest: encode_manifest(manifest),
              artifact: {
                filename: filename,
                content_type: "application/octet-stream",
                body: bytes
              }
            }
          )
        )
        PublishedVersion.from_payload(data)
      end

      # @param name [String] +namespace/skill+
      # @return [Skill]
      # @raise [Error]
      def get_skill(name)
        namespace, skill = split_name(name)
        Skill.from_payload(json_body(request(:get, skill_path(namespace, skill))))
      end

      # @param name [String] +namespace/skill+
      # @param version [String]
      # @return [Version]
      # @raise [Error]
      def get_version(name, version)
        namespace, skill = split_name(name)
        payload = json_body(
          request(:get, skill_path(namespace, skill, "versions", version))
        )
        Version.from_payload(payload)
      end

      # Resolve a RubyGems-style requirement to a published version.
      #
      # Fetches the skill, picks the highest compatible available version,
      # then loads that version's metadata.
      #
      # @param name [String] +namespace/skill+
      # @param requirement [String, Array, Gem::Requirement]
      # @return [Version]
      # @raise [Error] when nothing matches
      def resolve_version(name, requirement = "latest")
        skill = get_skill(name)
        resolved = VersionResolver.new(skill.versions, requirement).resolve
        unless resolved
          raise Error.new(
            "No compatible version for #{name} (#{requirement})",
            code: "not_found",
            status: 404
          )
        end

        get_version(name, resolved)
      end

      # Download artifact bytes for an exact version.
      #
      # @param name [String] +namespace/skill+
      # @param version [String]
      # @param destination [String, Pathname, nil] optional file to write
      # @return [Download]
      # @raise [Error]
      def download(name, version, destination: nil)
        namespace, skill = split_name(name)
        response = request(
          :get,
          skill_path(namespace, skill, "versions", version, "download")
        )
        bytes = response.body.to_s.b
        checksum = response.headers[CHECKSUM_HEADER].to_s
        checksum = Digest::SHA256.hexdigest(bytes) if checksum.empty?
        verify_checksum!(bytes, checksum)

        path = write_download(bytes, destination)
        Download.new(bytes: bytes, checksum: checksum, size: bytes.bytesize, path: path)
      end

      # @return [Array<Category>]
      # @raise [Error]
      def categories
        payload = json_body(request(:get, "/api/v1/categories"))
        rows = payload.is_a?(Array) ? payload : Array(payload["categories"])
        rows.map { |row| Category.from_payload(row) }
      end

      # @return [String]
      def inspect
        token = @token ? "[FILTERED]" : "nil"
        "#<#{self.class.name} base_url=#{@base_url.inspect} token=#{token}>"
      end

      private

      # @return [String]
      def default_base_url
        env = ENV.fetch(URL_ENV, nil).to_s.strip
        return env.chomp("/") unless env.empty?

        UserConfig.load.registry
      end

      # @return [String, nil]
      def default_token
        env = ENV.fetch(TOKEN_ENV, nil).to_s.strip
        return env unless env.empty?

        Credentials.load.token
      end

      # @return [void]
      # @raise [Error]
      def require_token!
        return unless @token.to_s.empty?

        raise Error.new(
          "API token is missing or invalid",
          code: "unauthenticated",
          status: 401
        )
      end

      # @param name [String]
      # @return [Array<String>]
      # @raise [Error]
      def split_name(name)
        namespace, skill, extra = name.to_s.split("/", 3)
        if extra || namespace.to_s.empty? || skill.to_s.empty?
          raise Error.new("#{name.inspect} must be namespace/name", code: "invalid_request")
        end

        [namespace, skill]
      end

      # @param segments [Array<String>]
      # @return [String]
      def skill_path(*segments)
        encoded = segments.map { |segment| encode_segment(segment) }
        "/api/v1/skills/#{encoded.join("/")}"
      end

      # @param value [String]
      # @return [String]
      def encode_segment(value)
        URI.encode_www_form_component(value.to_s).gsub("+", "%20")
      end

      # @param method [Symbol]
      # @param path [String]
      # @param json [Hash, nil]
      # @param form [Hash, nil]
      # @return [Response]
      # @raise [Error]
      def request(method, path, json: nil, form: nil)
        response = @http.request(
          method: method,
          path: path,
          headers: default_headers,
          json: json,
          form: form
        )
        raise_for_status!(response)
        response
      end

      # @return [Hash{String => String}]
      def default_headers
        headers = {
          "User-Agent" => format(USER_AGENT_FORMAT, RubySkills::VERSION),
          "Accept" => "application/json, application/octet-stream"
        }
        headers["Authorization"] = "Bearer #{@token}" unless @token.to_s.empty?
        headers
      end

      # @param response [Response]
      # @return [void]
      # @raise [Error]
      def raise_for_status!(response)
        return if (200..299).cover?(response.status)

        payload = parse_json(response.body)
        error = payload.is_a?(Hash) ? payload["error"] : nil
        message = error.is_a?(Hash) ? error["message"] : nil
        code = error.is_a?(Hash) ? error["code"] : nil

        raise Error.new(
          message || "Registry request failed (HTTP #{response.status})",
          code: code || "http_error",
          status: response.status
        )
      end

      # @param response [Response]
      # @return [Hash]
      # @raise [Error]
      def json_body(response)
        payload = parse_json(response.body)
        return payload if payload.is_a?(Hash) || payload.is_a?(Array)

        raise Error.new(
          "Registry returned invalid JSON",
          code: "http_error",
          status: response.status
        )
      end

      # @param body [String]
      # @return [Object, nil]
      def parse_json(body)
        return if body.to_s.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      # @param manifest [Hash, String]
      # @return [String]
      def encode_manifest(manifest)
        manifest.is_a?(String) ? manifest : JSON.generate(manifest)
      end

      # @param artifact [String, Pathname]
      # @return [Array(String, String)]
      def read_artifact(artifact)
        path = Pathname.new(artifact)
        raise Error.new("Artifact not found: #{path}", code: "invalid_request") unless path.file?

        [path.basename.to_s, path.binread]
      end

      # @param bytes [String]
      # @param checksum [String]
      # @return [void]
      # @raise [Error]
      def verify_checksum!(bytes, checksum)
        actual = Digest::SHA256.hexdigest(bytes)
        return if actual.casecmp(checksum).zero?

        raise Error.new(
          "Checksum mismatch",
          code: "checksum_mismatch",
          status: 422
        )
      end

      # @param bytes [String]
      # @param destination [String, Pathname, nil]
      # @return [Pathname, nil]
      def write_download(bytes, destination)
        return unless destination

        path = Pathname.new(destination)
        FileUtils.mkdir_p(path.dirname)
        path.binwrite(bytes)
        path
      end
    end
  end
end
