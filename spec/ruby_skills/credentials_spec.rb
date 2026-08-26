# frozen_string_literal: true

RSpec.describe RubySkills::Credentials do
  let(:token) { "rsk_#{"a" * 64}" }

  describe "#update_token!" do
    it "writes credentials.yml with 0600 permissions" do
      with_user_config_home do |directory|
        described_class.load.update_token!(token)
        file = directory.join("credentials.yml")

        expect(file).to be_file
        expect(file.stat.mode & 0o777).to eq(0o600)
        expect(directory.stat.mode & 0o777).to eq(0o700)
        expect(YAML.safe_load(file.read)).to eq("token" => token)
      end
    end

    it "does not store the token in config.yml" do
      with_user_config_home do |directory|
        described_class.load.update_token!(token)

        expect(directory.join("config.yml")).not_to exist
      end
    end

    it "rejects a blank token" do
      with_user_config_home do
        expect {
          described_class.load.update_token!("  ")
        }.to raise_error(RubySkills::Error, "Token is required")
      end
    end

    it "rejects a non-string token" do
      with_user_config_home do
        expect {
          described_class.load.update_token!(true)
        }.to raise_error(RubySkills::Error, "Token is required")
      end
    end

    it "rejects a token that does not start with rsk_" do
      with_user_config_home do
        expect {
          described_class.load.update_token!("true")
        }.to raise_error(RubySkills::Error, "Token must start with rsk_")
      end
    end
  end

  describe "#token" do
    it "returns nil when the file is missing" do
      with_user_config_home do
        expect(described_class.load.token).to be_nil
      end
    end

    it "reads the stored token" do
      with_user_config_home do
        described_class.load.update_token!(token)

        expect(described_class.load.token).to eq(token)
      end
    end
  end

  describe "#clear!" do
    it "deletes credentials.yml" do
      with_user_config_home do |directory|
        store = described_class.load
        store.update_token!(token)
        store.clear!

        expect(directory.join("credentials.yml")).not_to exist
        expect(described_class.load.token).to be_nil
      end
    end
  end

  describe "#inspect" do
    it "does not leak the token" do
      with_user_config_home do
        store = described_class.load
        store.update_token!(token)

        expect(store.inspect).to include("[FILTERED]")
        expect(store.inspect).not_to include(token)
      end
    end
  end
end
