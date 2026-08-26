# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::CLI do
  describe "version" do
    it "prints the gem version" do
      expect {
        described_class.start(["version"])
      }.to output("ruby-skills #{RubySkills::VERSION}\n").to_stdout
    end
  end

  describe "config" do
    it "prints the default registry when no config file exists" do
      with_user_config_home do
        expect {
          described_class.start(["config"])
        }.to output("registry: https://rubyskills.org\n").to_stdout
      end
    end

    it "writes registry to ~/.config/ruby-skills/config.yml" do
      with_user_config_home do |directory|
        expect {
          described_class.start(
            ["config", "registry", "https://staging.rubyskills.org"]
          )
        }.to output("registry: https://staging.rubyskills.org\n").to_stdout

        expect(directory.join("config.yml")).to be_file
        expect(YAML.safe_load(directory.join("config.yml").read)).to eq(
          "registry" => "https://staging.rubyskills.org"
        )
      end
    end

    it "prints the stored registry" do
      with_user_config_home do
        RubySkills::UserConfig.load.update_registry!("http://localhost:3000")

        expect {
          described_class.start(%w[config registry])
        }.to output("registry: http://localhost:3000\n").to_stdout
      end
    end

    it "rejects an invalid registry URL" do
      with_user_config_home do
        expect {
          expect {
            described_class.start(["config", "registry", "not-a-url"])
          }.to output(/Invalid registry URL/).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end
  end

  describe "login" do
    let(:token) { "rsk_#{"a" * 64}" }

    it "saves --token to credentials.yml without printing it" do
      with_user_config_home do |directory|
        expect {
          described_class.start(["login", "--token", token])
        }.to output("Logged in.\n").to_stdout

        file = directory.join("credentials.yml")
        expect(file).to be_file
        expect(file.stat.mode & 0o777).to eq(0o600)
        expect(YAML.safe_load(file.read)).to eq("token" => token)
        expect(directory.join("config.yml")).not_to exist
      end
    end

    it "explains how to pass a token when --token is omitted" do
      with_user_config_home do
        expect {
          expect {
            described_class.start(["login"])
          }.to output(
            a_string_including(
              "Browser sign-in is not available yet.",
              "ruby-skills login --token rsk_..."
            )
          ).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }

        expect(RubySkills::Credentials.load.token).to be_nil
      end
    end
  end

  describe "logout" do
    it "removes the saved token" do
      with_user_config_home do |directory|
        RubySkills::Credentials.load.update_token!("rsk_secret")

        expect {
          described_class.start(["logout"])
        }.to output("Logged out.\n").to_stdout

        expect(directory.join("credentials.yml")).not_to exist
      end
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

  describe "build" do
    def seed_skill(root)
      skill = root.join("request-specs")
      RubySkills::Generators::Skill.new(root: root).create("rails/request-specs")
      skill.join("references", "http.md").write("# http\n")
      skill.join("references", "status.md").write("# status\n")
      skill
    end

    it "writes a .rskill to pkg/ and prints the build report" do
      with_tmp_project do |root|
        skill = seed_skill(root)
        artifact = root.join("pkg", "rails-request-specs-0.1.0.rskill")

        expect {
          described_class.start(["build", skill.to_s])
        }.to output(
          a_string_including(
            "Building rails/request-specs 0.1.0",
            "✓ manifest valid",
            "✓ 4 files included",
            "✓ artifact created",
            "pkg/rails-request-specs-0.1.0.rskill",
            "SHA256:",
            "Size:"
          ).and(satisfy { |text|
            text.include?(Digest::SHA256.file(artifact).hexdigest)
          })
        ).to_stdout

        expect(artifact).to be_file
      end
    end

    it "writes the artifact to --output" do
      with_tmp_project do |root|
        skill = seed_skill(root)

        expect {
          described_class.start(["build", skill.to_s, "--output", "dist/"])
        }.to output(
          a_string_including(
            "dist/rails-request-specs-0.1.0.rskill",
            "✓ artifact created"
          )
        ).to_stdout

        expect(root.join("dist", "rails-request-specs-0.1.0.rskill")).to be_file
        expect(root.join("pkg")).not_to exist
      end
    end

    it "builds the current directory when PATH is omitted" do
      with_tmp_project do |root|
        RubySkills::Generators::Skill.new(root: root).create(
          "rails/request-specs",
          in_place: true
        )

        expect {
          described_class.start(["build"])
        }.to output(%r{pkg/rails-request-specs-0.1.0.rskill}).to_stdout

        expect(root.join("pkg", "rails-request-specs-0.1.0.rskill")).to be_file
      end
    end

    it "does not write an artifact when validation fails" do
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
            "files" => ["SKILL.md"]
          }.to_yaml
        )

        expect {
          expect {
            described_class.start(["build", skill.to_s])
          }.to output(
            a_string_including(
              "Building rails/request-specs foo",
              %(✗ version: "foo" is invalid),
              "Skill is invalid."
            )
          ).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }

        expect(root.join("pkg")).not_to exist
        expect(Dir["#{root}/**/*.rskill"]).to eq([])
      end
    end
  end

  describe "info" do
    def stub_registry_client(http)
      client = RubySkills::Registry::Client.new(
        base_url: "https://rubyskills.org",
        http: http
      )
      allow(RubySkills::Registry::Client).to receive(:new).and_return(client)
    end

    it "prints registry metadata without writing files" do
      with_tmp_project do |root|
        http = RubySkillsSpec::FakeRegistryHttp.new
        http.stub(
          :get,
          "/api/v1/skills/rails/request-specs",
          status: 200,
          body: {
            "name" => "rails/request-specs",
            "summary" => "Practices for writing Rails request specs.",
            "latest_version" => "1.4.2",
            "downloads" => 12_842,
            "categories" => [{ "slug" => "testing", "name" => "Testing" }],
            "versions" => %w[1.4.2 1.4.1 1.3.0]
          }
        )
        stub_registry_client(http)

        expect {
          described_class.start(["info", "rails/request-specs"])
        }.to output(<<~TEXT).to_stdout
          rails/request-specs

          Practices for writing Rails request specs.

          Latest
          1.4.2

          Categories
          Testing

          Versions
          1.4.2
          1.4.1
          1.3.0

          Downloads
          12,842

          Install
          ruby-skills install rails/request-specs
        TEXT

        expect(root.children).to be_empty
      end
    end

    it "exits 1 when the skill is missing" do
      http = RubySkillsSpec::FakeRegistryHttp.new
      http.stub(
        :get,
        "/api/v1/skills/rails/missing",
        status: 404,
        body: { "error" => { "code" => "not_found", "message" => "Skill not found" } }
      )
      stub_registry_client(http)

      expect {
        expect {
          described_class.start(["info", "rails/missing"])
        }.to output(/Error: Skill not found/).to_stdout
      }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end
  end

  describe "publish" do
    def seed_skill(root)
      skill = root.join("request-specs")
      RubySkills::Generators::Skill.new(root: root).create("rails/request-specs")
      skill.join("references", "http.md").write("# http\n")
      skill
    end

    def stub_registry_client(http, token: "rsk_secret")
      client = RubySkills::Registry::Client.new(
        base_url: "https://rubyskills.org",
        token: token,
        http: http
      )
      allow(RubySkills::Registry::Client).to receive(:new).and_return(client)
    end

    it "prints the success report after a registry upload" do
      with_user_config_home do
        with_tmp_project do |root|
          skill = seed_skill(root)
          http = RubySkillsSpec::FakeRegistryHttp.new
          http.stub(
            :post,
            "/api/v1/skills/rails/request-specs/versions",
            status: 201,
            body: {
              "name" => "rails/request-specs",
              "version" => "0.1.0",
              "checksum" => "abc",
              "published_at" => "2026-08-25T00:00:00Z",
              "url" => "https://rubyskills.org/rails/request-specs",
              "version_url" => "https://rubyskills.org/rails/request-specs/versions/0.1.0"
            }
          )
          stub_registry_client(http)

          expect {
            described_class.start(["publish", skill.to_s])
          }.to output(
            a_string_including(
              "Publishing rails/request-specs 0.1.0",
              "✓ manifest validated",
              "✓ artifact built",
              "✓ checksum verified",
              "✓ uploaded",
              "✓ published",
              "rails/request-specs 0.1.0 published successfully",
              "https://rubyskills.org/rails/request-specs"
            )
          ).to_stdout
        end
      end
    end

    it "explains that published versions are immutable on conflict" do
      with_user_config_home do
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
          stub_registry_client(http)

          expect {
            expect {
              described_class.start(["publish", skill.to_s])
            }.to output(
              a_string_including(
                "✗ rails/request-specs 0.1.0 already exists.",
                "Published versions are immutable.",
                "Increment the version in skill.yml and try again."
              )
            ).to_stdout
          }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end
      end
    end

    it "asks the user to log in when no token is stored" do
      with_user_config_home do
        with_tmp_project do |root|
          skill = seed_skill(root)

          expect {
            expect {
              described_class.start(["publish", skill.to_s])
            }.to output(
              a_string_including(
                "Publishing rails/request-specs 0.1.0",
                "✗ not logged in.",
                "ruby-skills login --token rsk_..."
              )
            ).to_stdout
          }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end
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
