# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::Registry::Client do
  def skill_payload
    {
      "name" => "rails/request-specs",
      "summary" => "Request spec conventions for Rails apps.",
      "latest_version" => "1.4.2",
      "categories" => [{ "slug" => "testing", "name" => "Testing" }],
      "versions" => %w[1.4.2 1.3.0]
    }
  end

  def version_payload
    {
      "name" => "rails/request-specs",
      "version" => "1.4.2",
      "checksum" => "abc123",
      "manifest" => { "name" => "request-specs" },
      "published_at" => "2026-08-25T00:00:00Z",
      "yanked" => false,
      "download_url" => "https://rubyskills.org/api/v1/skills/rails/request-specs/versions/1.4.2/download"
    }
  end

  def client_for(http, token: nil)
    described_class.new(base_url: "https://rubyskills.org", token: token, http: http)
  end

  describe "#authenticate" do
    it "issues a token and stores it for later requests" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :post,
        "/api/v1/auth/token",
        status: 201,
        body: { "token" => "rsk_secret", "token_type" => "Bearer" }
      )
      client = client_for(http)

      result = client.authenticate(email: "dev@example.com", password: "secret")

      expect(result).to have_attributes(token: "rsk_secret", token_type: "Bearer")
      expect(client.token).to eq("rsk_secret")
      expect(http.requests.last.json).to eq(email: "dev@example.com", password: "secret")
    end

    it "sends otp_code when given" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :post,
        "/api/v1/auth/token",
        status: 201,
        body: { "token" => "rsk_otp", "token_type" => "Bearer" }
      )

      client_for(http).authenticate(
        email: "dev@example.com",
        password: "secret",
        otp_code: "123456"
      )

      expect(http.requests.last.json[:otp_code]).to eq("123456")
    end

    it "raises on invalid credentials" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :post,
        "/api/v1/auth/token",
        status: 401,
        body: {
          "error" => {
            "code" => "unauthenticated",
            "message" => "Email or password is invalid"
          }
        }
      )

      expect {
        client_for(http).authenticate(email: "dev@example.com", password: "nope")
      }.to raise_error(RubySkills::Registry::Error, "Email or password is invalid")
    end
  end

  describe "#get_skill" do
    it "returns public skill metadata" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(:get, "/api/v1/skills/rails/request-specs", status: 200, body: skill_payload)

      skill = client_for(http).get_skill("rails/request-specs")

      expect(skill).to have_attributes(
        name: "rails/request-specs",
        summary: "Request spec conventions for Rails apps.",
        latest_version: "1.4.2",
        versions: %w[1.4.2 1.3.0]
      )
      expect(skill.categories.first).to have_attributes(slug: "testing", name: "Testing")
    end

    it "raises when the skill is missing" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :get,
        "/api/v1/skills/rails/missing",
        status: 404,
        body: { "error" => { "code" => "not_found", "message" => "Skill not found" } }
      )

      expect {
        client_for(http).get_skill("rails/missing")
      }.to raise_error(RubySkills::Registry::Error, "Skill not found")
    end
  end

  describe "#get_version" do
    it "returns version metadata including the download URL" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs/versions/1.4.2",
        status: 200,
        body: version_payload
      )

      version = client_for(http).get_version("rails/request-specs", "1.4.2")

      expect(version).to have_attributes(
        name: "rails/request-specs",
        version: "1.4.2",
        checksum: "abc123",
        yanked: false
      )
      expect(version.download_url).to include("/download")
    end
  end

  describe "#resolve_version" do
    it "picks the highest compatible version and loads it" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(:get, "/api/v1/skills/rails/request-specs", status: 200, body: skill_payload)
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs/versions/1.3.0",
        status: 200,
        body: version_payload.merge("version" => "1.3.0")
      )

      version = client_for(http).resolve_version("rails/request-specs", "~> 1.3.0")

      expect(version.version).to eq("1.3.0")
    end

    it "raises when no published version matches" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(:get, "/api/v1/skills/rails/request-specs", status: 200, body: skill_payload)

      expect {
        client_for(http).resolve_version("rails/request-specs", "~> 9.0")
      }.to raise_error(RubySkills::Registry::Error, /No compatible version/)
    end
  end

  describe "#download" do
    it "returns artifact bytes and verifies the checksum header" do
      bytes = "opaque-install-bytes"
      checksum = Digest::SHA256.hexdigest(bytes)
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs/versions/1.4.2/download",
        status: 200,
        body: bytes,
        headers: { "X-Ruby-Skills-SHA256" => checksum }
      )

      result = client_for(http).download("rails/request-specs", "1.4.2")

      expect(result.bytes).to eq(bytes)
      expect(result.checksum).to eq(checksum)
      expect(result.size).to eq(bytes.bytesize)
      expect(result.path).to be_nil
    end

    it "writes the artifact when destination is given" do
      bytes = "opaque-install-bytes"
      checksum = Digest::SHA256.hexdigest(bytes)
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs/versions/1.4.2/download",
        status: 200,
        body: bytes,
        headers: { "x-ruby-skills-sha256" => checksum }
      )

      with_tmp_project do |root|
        path = root.join("pkg", "rails-request-specs-1.4.2.rskill")
        result = client_for(http).download("rails/request-specs", "1.4.2", destination: path)

        expect(path.binread).to eq(bytes)
        expect(result.path).to eq(path)
      end
    end

    it "rejects a checksum mismatch" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs/versions/1.4.2/download",
        status: 200,
        body: "bytes",
        headers: { "x-ruby-skills-sha256" => "deadbeef" }
      )

      expect {
        client_for(http).download("rails/request-specs", "1.4.2")
      }.to raise_error(RubySkills::Registry::Error, "Checksum mismatch")
    end
  end

  describe "#publish_version" do
    it "uploads the artifact with a bearer token" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :post,
        "/api/v1/skills/rails/request-specs/versions",
        status: 201,
        body: {
          "name" => "rails/request-specs",
          "version" => "1.0.0",
          "checksum" => "abc",
          "published_at" => "2026-08-25T00:00:00Z",
          "url" => "https://rubyskills.org/rails/request-specs",
          "version_url" => "https://rubyskills.org/rails/request-specs/versions/1.0.0"
        }
      )

      with_tmp_project do |root|
        artifact = root.join("rails-request-specs-1.0.0.rskill")
        artifact.binwrite("package-bytes")
        client = client_for(http, token: "rsk_secret")

        result = client.publish_version(
          name: "rails/request-specs",
          version: "1.0.0",
          checksum: "abc",
          manifest: { "name" => "request-specs" },
          artifact: artifact
        )

        request = http.requests.last
        expect(request.headers["Authorization"]).to eq("Bearer rsk_secret")
        expect(request.form[:version]).to eq("1.0.0")
        expect(request.form[:artifact][:filename]).to eq("rails-request-specs-1.0.0.rskill")
        expect(request.form[:artifact][:body]).to eq("package-bytes")
        expect(result).to have_attributes(name: "rails/request-specs", version: "1.0.0")
      end
    end

    it "refuses to publish without a token" do
      expect {
        client_for(RubySkillsSpec::FakeRegistryHttp.new).publish_version(
          name: "rails/request-specs",
          version: "1.0.0",
          checksum: "abc",
          manifest: {},
          artifact: "missing.rskill"
        )
      }.to raise_error(RubySkills::Registry::Error, "API token is missing or invalid")
    end
  end

  describe "#categories" do
    it "lists registry categories" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :get,
        "/api/v1/categories",
        status: 200,
        body: [{ "slug" => "testing", "name" => "Testing" }]
      )

      result = client_for(http).categories

      expect(result.size).to eq(1)
      expect(result.first).to have_attributes(slug: "testing", name: "Testing")
    end
  end

  describe "#inspect" do
    it "does not leak the API token" do
      client = described_class.new(
        base_url: "https://rubyskills.org",
        token: "rsk_secret",
        http: RubySkillsSpec::FakeRegistryHttp.new
      )

      expect(client.inspect).to include("[FILTERED]")
      expect(client.inspect).not_to include("rsk_secret")
    end
  end

  describe "default registry" do
    it "reads registry from the user config file" do
      with_user_config_home do
        RubySkills::UserConfig.load.update_registry!("http://localhost:3000")
        client = described_class.new(http: RubySkillsSpec::FakeRegistryHttp.new)

        expect(client.base_url).to eq("http://localhost:3000")
      end
    end

    it "prefers RUBY_SKILLS_REGISTRY_URL over the config file" do
      with_user_config_home do
        RubySkills::UserConfig.load.update_registry!("http://localhost:3000")
        ENV["RUBY_SKILLS_REGISTRY_URL"] = "https://staging.rubyskills.org"
        client = described_class.new(http: RubySkillsSpec::FakeRegistryHttp.new)

        expect(client.base_url).to eq("https://staging.rubyskills.org")
      end
    end
  end

  describe "default token" do
    it "reads the token from credentials.yml" do
      with_user_config_home do
        RubySkills::Credentials.load.update_token!("rsk_file")
        client = described_class.new(
          base_url: "https://rubyskills.org",
          http: RubySkillsSpec::FakeRegistryHttp.new
        )

        expect(client.token).to eq("rsk_file")
      end
    end

    it "prefers RUBY_SKILLS_API_TOKEN over credentials.yml" do
      with_user_config_home do
        RubySkills::Credentials.load.update_token!("rsk_file")
        ENV["RUBY_SKILLS_API_TOKEN"] = "rsk_env"
        client = described_class.new(
          base_url: "https://rubyskills.org",
          http: RubySkillsSpec::FakeRegistryHttp.new
        )

        expect(client.token).to eq("rsk_env")
      end
    end
  end

  it "rejects locators that are not namespace/name" do
    client = client_for(RubySkillsSpec::FakeRegistryHttp.new)

    expect {
      client.get_skill("request-specs")
    }.to raise_error(RubySkills::Registry::Error, %r{namespace/name})
  end
end
