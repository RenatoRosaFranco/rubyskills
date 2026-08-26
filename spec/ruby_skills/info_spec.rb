# frozen_string_literal: true

RSpec.describe RubySkills::Info do
  def skill_payload
    {
      "name" => "rails/request-specs",
      "summary" => "Practices for writing Rails request specs.",
      "latest_version" => "1.4.2",
      "downloads" => 12_842,
      "categories" => [{ "slug" => "testing", "name" => "Testing" }],
      "versions" => %w[1.4.2 1.4.1 1.3.0]
    }
  end

  def client_for(http)
    RubySkills::Registry::Client.new(
      base_url: "https://rubyskills.org",
      http: http
    )
  end

  it "returns registry metadata without requiring a token" do
    http = RubySkillsSpec::FakeRegistryHttp.new
    http.stub(:get, "/api/v1/skills/rails/request-specs", status: 200, body: skill_payload)

    result = described_class.new("rails/request-specs", client: client_for(http)).run

    expect(result).to be_success
    expect(result.skill).to have_attributes(
      name: "rails/request-specs",
      latest_version: "1.4.2",
      downloads: 12_842,
      versions: %w[1.4.2 1.4.1 1.3.0]
    )
    expect(http.requests.last.headers["Authorization"]).to be_nil
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
