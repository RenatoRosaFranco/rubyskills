# frozen_string_literal: true

RSpec.describe RubySkills::CLI do
  describe "version" do
    it "prints the gem version" do
      expect {
        described_class.start(["version"])
      }.to output("ruby-skills #{RubySkills::VERSION}\n").to_stdout
    end
  end

  describe "list" do
    it "prints a message when no skills are installed" do
      with_tmp_project do
        expect {
          described_class.start(["list"])
        }.to output("No skills installed.\n").to_stdout
      end
    end

    it "prints a table of installed skills" do
      with_tmp_project do |root|
        RubySkills::Lockfile.new(
          config: RubySkills::Config.new(root: root)
        ).add(
          "rails-performance",
          version: "0.1.0",
          source: "github:username/rails-performance"
        )

        expect {
          described_class.start(["list"])
        }.to output(
          a_string_including("Installed skills:", "rails-performance", "0.1.0")
        ).to_stdout
      end
    end

    it "prints JSON when --json is given" do
      with_tmp_project do |root|
        RubySkills::Lockfile.new(
          config: RubySkills::Config.new(root: root)
        ).add(
          "rails-performance",
          version: "0.1.0",
          source: "github:username/rails-performance"
        )

        expect {
          described_class.start(["list", "--json"])
        }.to output(
          "#{JSON.generate(
            "skills" => [
              {
                "name" => "rails-performance",
                "version" => "0.1.0",
                "source" => "github:username/rails-performance"
              }
            ]
          )}\n"
        ).to_stdout
      end
    end

    it "prints an empty skills array when --json and nothing is installed" do
      with_tmp_project do
        expect {
          described_class.start(["list", "--json"])
        }.to output("#{{ "skills" => [] }.to_json}\n").to_stdout
      end
    end
  end

  describe "init" do
    it "creates Skillfile and .ruby-skills" do
      with_tmp_project do |root|
        expect {
          described_class.start(["init"])
        }.to output(/Ruby Skills initialized/).to_stdout

        expect(root.join("Skillfile")).to be_file
        expect(root.join(".ruby-skills")).to be_directory
      end
    end
  end

  describe "install" do
    it "exits with an error when the Skillfile is missing" do
      with_tmp_project do
        expect {
          expect {
            described_class.start(["install"])
          }.to output(/Error: Skillfile not found/).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end
  end
end
