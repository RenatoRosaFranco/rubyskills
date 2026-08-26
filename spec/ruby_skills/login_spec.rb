# frozen_string_literal: true

RSpec.describe RubySkills::Login do
  let(:token) { "rsk_#{"a" * 64}" }

  def client_for(http)
    RubySkills::Registry::Client.new(
      base_url: "https://rubyskills.org",
      token: nil,
      http: http
    )
  end

  it "stores a pasted token without talking to the registry" do
    with_user_config_home do
      http = RubySkillsSpec::FakeRegistryHttp.new

      result = described_class.new(token: token, client: client_for(http)).run

      expect(result).to be_success
      expect(RubySkills::Credentials.load.token).to eq(token)
      expect(http.requests).to be_empty
    end
  end

  it "polls a browser grant and stores the issued token" do
    with_user_config_home do
      issued = "rsk_#{"d" * 64}"
      opened = []
      uri = "https://rubyskills.org/cli/authorize/abc"
      http = RubySkillsSpec::FakeRegistryHttp.new.stub_device_login(issued: issued, uri: uri)

      result = described_class.new(
        client: client_for(http),
        opener: ->(url) { opened << url },
        sleeper: ->(_) {}
      ).run

      expect(result).to be_success
      expect(opened).to eq([uri])
      expect(RubySkills::Credentials.load.token).to eq(issued)
    end
  end
end
