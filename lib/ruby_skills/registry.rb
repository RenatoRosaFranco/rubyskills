# frozen_string_literal: true

require "json"

module RubySkills
  # First-party registry at +rubyskills.org+.
  #
  # HTTP lives here so CLI commands and application services never call
  # +Net::HTTP+ or Faraday directly.
  #
  # @see RubySkills::Registry::Client
  # @since 0.1.0
  module Registry
    # Default origin for {Client}.
    DEFAULT_URL = "https://rubyskills.org"

    # Environment variable for {Client} +base_url+.
    URL_ENV = "RUBY_SKILLS_REGISTRY_URL"

    # Environment variable for {Client} +token+.
    TOKEN_ENV = "RUBY_SKILLS_API_TOKEN"

    # Raised when a registry request fails.
    class Error < RubySkills::Error
      # @return [String, nil] API error code (+not_found+, +unauthenticated+, ...)
      attr_reader :code

      # @return [Integer, nil] HTTP status
      attr_reader :status

      # @param message [String, nil]
      # @param code [String, nil]
      # @param status [Integer, nil]
      def initialize(message = nil, code: nil, status: nil)
        @code = code
        @status = status
        super(message || "Registry request failed")
      end
    end

    # Raw HTTP result used by {Http} and test doubles.
    Response = Struct.new(:status, :headers, :body, keyword_init: true)

    # Issued API token from +POST /api/v1/auth/token+.
    Token = Struct.new(:token, :token_type, keyword_init: true)

    # Logged-in registry user from +GET /api/v1/auth/me+.
    CurrentUser = Struct.new(:username, :email, keyword_init: true) do
      # @param payload [Hash]
      # @return [CurrentUser]
      def self.from_payload(payload)
        new(username: payload["username"], email: payload["email"])
      end
    end

    # Pending browser login from +POST /api/v1/auth/device+.
    DeviceLogin = Struct.new(
      :device_code, :verification_uri, :expires_in, :interval,
      keyword_init: true
    ) do
      # @param payload [Hash]
      # @return [DeviceLogin]
      def self.from_payload(payload)
        new(
          device_code: payload["device_code"],
          verification_uri: payload["verification_uri"],
          expires_in: payload["expires_in"].to_i,
          interval: payload.fetch("interval", 5).to_i
        )
      end
    end

    # Registry category.
    Category = Struct.new(:slug, :name, keyword_init: true) do
      # @param payload [Hash]
      # @return [Category]
      def self.from_payload(payload)
        new(slug: payload["slug"], name: payload["name"])
      end
    end

    # Public skill metadata from +GET /api/v1/skills/:namespace/:skill+.
    Skill = Struct.new(
      :name, :summary, :latest_version, :categories, :versions, :downloads,
      keyword_init: true
    ) do
      # @param payload [Hash]
      # @return [Skill]
      def self.from_payload(payload)
        new(
          name: payload["name"],
          summary: payload["summary"],
          latest_version: payload["latest_version"],
          categories: Array(payload["categories"]).map { |row| Category.from_payload(row) },
          versions: Array(payload["versions"]),
          downloads: payload.fetch("downloads", 0).to_i
        )
      end
    end

    # Published version metadata.
    Version = Struct.new(
      :name, :version, :checksum, :manifest, :published_at, :yanked, :download_url,
      :dependencies,
      keyword_init: true
    ) do
      # @param payload [Hash]
      # @return [Version]
      def self.from_payload(payload)
        new(
          name: payload["name"],
          version: payload["version"],
          checksum: payload["checksum"],
          manifest: payload["manifest"] || {},
          published_at: payload["published_at"],
          yanked: payload["yanked"],
          download_url: payload["download_url"],
          dependencies: Array(payload["dependencies"]).filter_map { |row|
            next unless row.is_a?(Hash)

            { "name" => row["name"], "requirement" => row["requirement"] }
          }
        )
      end
    end

    # +201 Created+ body after publish.
    PublishedVersion = Struct.new(
      :name, :version, :checksum, :published_at, :url, :version_url,
      keyword_init: true
    ) do
      # @param payload [Hash]
      # @return [PublishedVersion]
      def self.from_payload(payload)
        new(
          name: payload["name"],
          version: payload["version"],
          checksum: payload["checksum"],
          published_at: payload["published_at"],
          url: payload["url"],
          version_url: payload["version_url"]
        )
      end
    end

    # Downloaded +.rskill+ bytes.
    class Download
      # @return [String]
      attr_reader :bytes

      # @return [String]
      attr_reader :checksum

      # @return [Integer]
      attr_reader :size

      # @return [Pathname, nil]
      attr_reader :path

      # @param bytes [String]
      # @param checksum [String]
      # @param size [Integer]
      # @param path [Pathname, nil]
      def initialize(bytes:, checksum:, size:, path:)
        @bytes = bytes
        @checksum = checksum
        @size = size
        @path = path
      end
    end
  end
end
