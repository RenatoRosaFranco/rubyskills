# frozen_string_literal: true

RSpec.describe RubySkills::Publish do
  def seed_skill(root)
    skill = root.join("request-specs")
    RubySkills::Generators::Skill.new(root: root).create("rails/request-specs")
    skill.join("references", "http.md").write("# http\n")
    skill
  end

  def published_payload
    {
      "name" => "rails/request-specs",
      "version" => "0.1.0",
      "checksum" => "abc",
      "published_at" => "2026-08-25T00:00:00Z",
      "url" => "https://rubyskills.org/rails/request-specs",
      "version_url" => "https://rubyskills.org/rails/request-specs/versions/0.1.0"
    }
  end

  def client_for(http, token: "rsk_secret")
    RubySkills::Registry::Client.new(
      base_url: "https://rubyskills.org",
      token: token,
      http: http
    )
  end

  def publish(skill, http, token: "rsk_secret")
    described_class.new(
      skill,
      client: client_for(http, token: token),
      output: skill.parent.join("pkg")
    ).run
  end

  it "validates, builds, verifies checksum and uploads" do
    with_tmp_project do |root|
      skill = seed_skill(root)
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :post,
        "/api/v1/skills/rails/request-specs/versions",
        status: 201,
        body: published_payload
      )

      result = publish(skill, http)

      expect(result).to be_success
      expect(result.status).to eq(:published)
      expect(result.published.url).to eq("https://rubyskills.org/rails/request-specs")
      expect(http.requests.size).to eq(1)
      expect(http.requests.last.form[:version]).to eq("0.1.0")
      expect(http.requests.last.form[:checksum]).to match(/\A[a-f0-9]{64}\z/)
    end
  end

  it "does not upload when validation fails" do
    with_tmp_project do |root|
      skill = root.join("request-specs")
      FileUtils.mkdir_p(skill)
      skill.join("skill.yml").write(
        {
          "name" => "request-specs",
          "namespace" => "rails",
          "version" => "foo",
          "summary" => "Broken.",
          "entrypoint" => "SKILL.md"
        }.to_yaml
      )
      http = RubySkillsSpec::FakeRegistryHttp.new

      result = publish(skill, http)

      expect(result.status).to eq(:invalid)
      expect(http.requests).to be_empty
    end
  end

  it "does not upload when no token is stored" do
    with_tmp_project do |root|
      skill = seed_skill(root)
      http = RubySkillsSpec::FakeRegistryHttp.new

      result = publish(skill, http, token: nil)

      expect(result.status).to eq(:unauthenticated)
      expect(http.requests).to be_empty
    end
  end

  it "maps version_already_exists to a conflict" do
    with_tmp_project do |root|
      skill = seed_skill(root)
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :post,
        "/api/v1/skills/rails/request-specs/versions",
        status: 409,
        body: {
          "error" => {
            "code" => "version_already_exists",
            "message" => "rails/request-specs 0.1.0 already exists"
          }
        }
      )

      result = publish(skill, http)

      expect(result.status).to eq(:conflict)
      expect(result.label).to eq("rails/request-specs 0.1.0")
    end
  end
end
