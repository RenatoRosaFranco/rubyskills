# frozen_string_literal: true

RSpec.describe RubySkills::Whoami do
  def client_for(http, token: "rsk_secret")
    RubySkills::Registry::Client.new(
      base_url: "https://rubyskills.org",
      token: token,
      http: http
    )
  end

  it "returns the logged-in username and email" do
    http = RubySkillsSpec::FakeRegistryHttp.new
    http.stub(
      :get,
      "/api/v1/auth/me",
      status: 200,
      body: { "username" => "johndoe", "email" => "johen@doe.com" }
    )

    result = described_class.new(client: client_for(http)).run

    expect(result).to be_success
    expect(result.user).to have_attributes(
      username: "johndoe",
      email: "johen@doe.com"
    )
    expect(http.requests.last.headers["Authorization"]).to eq("Bearer rsk_secret")
  end

  it "does not call the registry when no token is stored" do
    http = RubySkillsSpec::FakeRegistryHttp.new

    result = described_class.new(client: client_for(http, token: nil)).run

    expect(result).not_to be_success
    expect(result.status).to eq(:unauthenticated)
    expect(http.requests).to be_empty
  end

  it "treats a rejected token as not logged in" do
    http = RubySkillsSpec::FakeRegistryHttp.new
    http.stub(
      :get,
      "/api/v1/auth/me",
      status: 401,
      body: {
        "error" => {
          "code" => "unauthenticated",
          "message" => "API token is missing or invalid"
        }
      }
    )

    result = described_class.new(client: client_for(http)).run

    expect(result.status).to eq(:unauthenticated)
    expect(result.user).to be_nil
  end
end
