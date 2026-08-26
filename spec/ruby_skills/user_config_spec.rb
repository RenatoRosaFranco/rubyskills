# frozen_string_literal: true

RSpec.describe RubySkills::UserConfig do
  describe ".directory" do
    it "uses $XDG_CONFIG_HOME/ruby-skills when set" do
      with_user_config_home do |directory|
        expect(described_class.directory).to eq(directory)
        expect(described_class.path).to eq(directory.join("config.yml"))
      end
    end
  end

  describe "#registry" do
    it "defaults to production when the file is missing" do
      with_user_config_home do
        expect(described_class.load.registry).to eq("https://rubyskills.org")
      end
    end

    it "reads registry from config.yml" do
      with_user_config_home do |directory|
        FileUtils.mkdir_p(directory)
        directory.join("config.yml").write("registry: http://localhost:3000\n")

        expect(described_class.load.registry).to eq("http://localhost:3000")
      end
    end
  end

  describe "#update_registry!" do
    it "creates ~/.config/ruby-skills/config.yml" do
      with_user_config_home do |directory|
        described_class.load.update_registry!("https://staging.rubyskills.org")

        expect(directory.join("config.yml")).to be_file
        expect(YAML.safe_load(directory.join("config.yml").read)).to eq(
          "registry" => "https://staging.rubyskills.org"
        )
      end
    end

    it "accepts localhost for development" do
      with_user_config_home do
        expect(described_class.load.update_registry!("http://127.0.0.1:3000")).to eq(
          "http://127.0.0.1:3000"
        )
      end
    end

    it "rejects a URL that is not http(s)" do
      with_user_config_home do
        expect {
          described_class.load.update_registry!("ftp://example.com")
        }.to raise_error(RubySkills::Error, "Invalid registry URL: ftp://example.com")
      end
    end
  end
end
