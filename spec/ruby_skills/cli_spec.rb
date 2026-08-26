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
    it "creates a skill from namespace/name" do
      with_tmp_project do |root|
        expect {
          described_class.start(["init", "rails/request-specs"])
        }.to output(
          a_string_including(
            "Created Ruby Skill:",
            "request-specs/",
            "skill.yml",
            "SKILL.md",
            "references/",
            "cd request-specs",
            "ruby-skills validate"
          )
        ).to_stdout

        expect(root.join("request-specs", "skill.yml")).to be_file
        expect(root.join("request-specs", "SKILL.md")).to be_file
        expect(root.join("request-specs", "references")).to be_directory
      end
    end

    it "prompts for namespace and name in an empty directory" do
      with_tmp_project do |root|
        cli = described_class.new
        allow(cli).to receive(:ask).and_return("rails", "request-specs")

        expect { cli.init }.to output(/Created Ruby Skill:/).to_stdout

        expect(cli).to have_received(:ask).with("Namespace:")
        expect(cli).to have_received(:ask).with("Name:")
        expect(root.join("skill.yml")).to be_file
        expect(root.join("request-specs")).not_to exist
      end
    end

    it "refuses to overwrite an existing skill directory" do
      with_tmp_project do |root|
        root.join("request-specs").mkdir

        expect {
          expect {
            described_class.start(["init", "rails/request-specs"])
          }.to output(/Directory already exists: request-specs/).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    it "rejects an invalid skill name" do
      with_tmp_project do
        expect {
          expect {
            described_class.start(%w[init request-specs])
          }.to output(%r{namespace/name}).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    it "rejects init without a name in a non-empty directory" do
      with_tmp_project do |root|
        root.join("README.md").write("keep\n")

        expect {
          expect {
            described_class.start(["init"])
          }.to output(/Current directory is not empty/).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end
  end

  describe "validate" do
    it "prints a success report and exits 0" do
      with_tmp_project do |root|
        expect {
          described_class.start(%w[init rails/request-specs])
        }.to output(/Created Ruby Skill/).to_stdout
        skill = root.join("request-specs")
        skill.join("references", "http.md").write("# http\n")
        skill.join("references", "status.md").write("# status\n")

        expect {
          described_class.start(["validate", skill.to_s])
        }.to output(
          a_string_including(
            "Validating rails/request-specs 0.1.0",
            "✓ manifest valid",
            "✓ version valid",
            "✓ entrypoint exists",
            "✓ file paths are safe",
            "✓ 3 files included",
            "Skill is valid."
          )
        ).to_stdout
      end
    end

    it "validates the current directory when PATH is omitted" do
      with_tmp_project do |root|
        RubySkills::Generators::Skill.new(root: root).create(
          "rails/request-specs",
          in_place: true
        )

        expect {
          described_class.start(["validate"])
        }.to output(/Skill is valid/).to_stdout
      end
    end

    it "prints every failure and exits 1" do
      with_tmp_project do |root|
        skill = root.join("request-specs")
        FileUtils.mkdir_p(skill)
        skill.join("skill.yml").write(
          {
            "name" => "request-specs",
            "namespace" => "rails",
            "version" => "foo",
            "summary" => "Broken skill.",
            "entrypoint" => "SKILL.md",
            "files" => ["../secret"]
          }.to_yaml
        )

        expect {
          expect {
            described_class.start(["validate", skill.to_s])
          }.to output(
            a_string_including(
              "Validating rails/request-specs foo",
              %(✗ version: "foo" is invalid),
              "✗ entrypoint: SKILL.md does not exist",
              "✗ files: ../secret escapes the skill directory",
              "Skill is invalid."
            )
          ).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
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
