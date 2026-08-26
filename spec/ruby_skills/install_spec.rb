# frozen_string_literal: true

require "digest"
require "yaml"

RSpec.describe RubySkills::Install do
  def seed_skill(root, version: "1.4.2")
    skill = root.join("request-specs")
    RubySkills::Generators::Skill.new(root: root).create("rails/request-specs")
    skill.join("references", "http.md").write("# http\n")
    yaml = YAML.safe_load(skill.join("skill.yml").read)
    yaml["version"] = version
    skill.join("skill.yml").write(YAML.dump(yaml))
    skill
  end

  def build_artifact(skill, destination:)
    manifest = RubySkills::Manifest.load(skill)
    RubySkills::Artifact::Builder.new(
      root: skill,
      manifest: manifest,
      destination: destination
    ).build
  end

  def skill_payload(version: "1.4.2")
    {
      "name" => "rails/request-specs",
      "summary" => "Practices for writing Rails request specs.",
      "latest_version" => version,
      "downloads" => 12_842,
      "categories" => [{ "slug" => "testing", "name" => "Testing" }],
      "versions" => [version]
    }
  end

  def version_payload(checksum:, version: "1.4.2")
    {
      "name" => "rails/request-specs",
      "version" => version,
      "checksum" => checksum,
      "manifest" => { "name" => "request-specs" },
      "published_at" => "2026-08-25T00:00:00Z",
      "yanked" => false,
      "download_url" =>
        "https://rubyskills.org/api/v1/skills/rails/request-specs/versions/#{version}/download"
    }
  end

  def stub_registry(http, bytes:, checksum:, version: "1.4.2")
    http.stub(
      :get,
      "/api/v1/skills/rails/request-specs",
      status: 200,
      body: skill_payload(version: version)
    )
    http.stub(
      :get,
      "/api/v1/skills/rails/request-specs/versions/#{version}",
      status: 200,
      body: version_payload(checksum: checksum, version: version)
    )
    http.stub(
      :get,
      "/api/v1/skills/rails/request-specs/versions/#{version}/download",
      status: 200,
      body: bytes,
      headers: { "X-Ruby-Skills-SHA256" => checksum }
    )
  end

  def client_for(http)
    RubySkills::Registry::Client.new(
      base_url: "https://rubyskills.org",
      token: nil,
      http: http
    )
  end

  def install(name, http, root:)
    described_class.new(
      name,
      client: client_for(http),
      config: RubySkills::Config.new(root: root)
    ).run
  end

  it "recovers a published artifact byte-for-byte" do
    with_tmp_project do |root|
      machine_a = root.join("machine-a")
      machine_b = root.join("machine-b")
      FileUtils.mkdir_p([machine_a, machine_b])

      skill = seed_skill(machine_a)
      published = build_artifact(skill, destination: machine_a.join("pkg"))
      bytes = published.path.binread

      http = RubySkillsSpec::FakeRegistryHttp.new
      stub_registry(http, bytes: bytes, checksum: published.checksum)

      result = install("rails/request-specs", http, root: machine_b)
      installed = machine_b.join(".ruby-skills", "rails", "request-specs", "1.4.2")
      rebuilt = build_artifact(installed, destination: machine_b.join("pkg"))

      expect(result).to be_success
      expect(result.checksum).to eq(published.checksum)
      expect(rebuilt.checksum).to eq(published.checksum)
      expect(rebuilt.path.binread).to eq(bytes)
      expect(installed.join("SKILL.md").read).to eq(skill.join("SKILL.md").read)
      expect(installed.join("references", "http.md").read).to eq("# http\n")
    end
  end

  it "installs into .ruby-skills/namespace/name/version" do
    with_tmp_project do |root|
      published = build_artifact(seed_skill(root), destination: root.join("pkg"))
      http = RubySkillsSpec::FakeRegistryHttp.new
      stub_registry(http, bytes: published.path.binread, checksum: published.checksum)

      result = install("rails/request-specs", http, root: root)

      expect(result.path).to eq(root.join(".ruby-skills", "rails", "request-specs", "1.4.2"))
      expect(result.path.join("skill.yml")).to be_file
      expect(root.join("Skills.lock")).not_to exist
    end
  end

  it "does not write files when the registry checksum does not match" do
    with_tmp_project do |root|
      published = build_artifact(seed_skill(root), destination: root.join("pkg"))
      bytes = published.path.binread
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs",
        status: 200,
        body: skill_payload
      )
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs/versions/1.4.2",
        status: 200,
        body: version_payload(checksum: "a" * 64)
      )
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs/versions/1.4.2/download",
        status: 200,
        body: bytes,
        headers: { "X-Ruby-Skills-SHA256" => published.checksum }
      )

      result = install("rails/request-specs", http, root: root)

      expect(result).not_to be_success
      expect(result.error.message).to eq("Checksum mismatch")
      expect(root.join(".ruby-skills")).not_to exist
    end
  end

  it "does not require a token" do
    with_tmp_project do |root|
      published = build_artifact(seed_skill(root), destination: root.join("pkg"))
      http = RubySkillsSpec::FakeRegistryHttp.new
      stub_registry(http, bytes: published.path.binread, checksum: published.checksum)

      install("rails/request-specs", http, root: root)

      expect(http.requests.map { |req| req.headers["Authorization"] }).to all(be_nil)
    end
  end

  it "returns a failed result when the skill is missing" do
    http = RubySkillsSpec::FakeRegistryHttp.new
    http.stub(
      :get,
      "/api/v1/skills/rails/missing",
      status: 404,
      body: { "error" => { "code" => "not_found", "message" => "Skill not found" } }
    )

    result = described_class.new("rails/missing", client: client_for(http)).run

    expect(result).not_to be_success
    expect(result.error.message).to eq("Skill not found")
  end
end
