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

    it "does not treat --token without a value as a login" do
      with_user_config_home do
        expect {
          expect {
            described_class.start(["login", "--token"])
          }.to output(
            a_string_including(
              "Pass a token with --token",
              "ruby-skills login --token rsk_..."
            )
          ).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }

        expect(RubySkills::Credentials.load.token).to be_nil
      end
    end

    it "opens a browser login and stores the issued token" do
      with_user_config_home do |directory|
        issued = "rsk_#{"b" * 64}"
        uri = "https://rubyskills.org/cli/authorize/abc"
        http = RubySkillsSpec::FakeRegistryHttp.new.stub_device_login(issued: issued, uri: uri)
        client = RubySkills::Registry::Client.new(
          base_url: "https://rubyskills.org",
          token: nil,
          http: http
        )
        allow(RubySkills::Registry::Client).to receive(:new).and_return(client)
        allow(RubySkills::Browser).to receive(:open)

        expect {
          described_class.start(["login"])
        }.to output(
          a_string_including(
            "Opening a browser to authenticate.",
            uri,
            "Waiting for confirmation...",
            "Logged in."
          )
        ).to_stdout

        expect(RubySkills::Credentials.load.token).to eq(issued)
        expect(RubySkills::Browser).to have_received(:open).with(uri)
        expect(directory.join("credentials.yml")).to be_file
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

    it "does not claim to log out when no token is stored" do
      with_user_config_home do
        expect {
          described_class.start(["logout"])
        }.to output("Not logged in.\n").to_stdout
      end
    end
  end

  describe "whoami" do
    it "prints the logged-in username and email" do
      with_user_config_home do
        RubySkills::Credentials.load.update_token!("rsk_secret")
        http = RubySkillsSpec::FakeRegistryHttp.new
        http.stub(
          :get,
          "/api/v1/auth/me",
          status: 200,
          body: { "username" => "johndoe", "email" => "johen@doe.com" }
        )
        client = RubySkills::Registry::Client.new(
          base_url: "https://rubyskills.org",
          token: "rsk_secret",
          http: http
        )
        allow(RubySkills::Registry::Client).to receive(:new).and_return(client)

        expect {
          described_class.start(["whoami"])
        }.to output("username: johndoe\nemail:    johen@doe.com\n").to_stdout
      end
    end

    it "prints JSON when --json is given" do
      with_user_config_home do
        RubySkills::Credentials.load.update_token!("rsk_secret")
        http = RubySkillsSpec::FakeRegistryHttp.new
        http.stub(
          :get,
          "/api/v1/auth/me",
          status: 200,
          body: { "username" => "johndoe", "email" => "johen@doe.com" }
        )
        client = RubySkills::Registry::Client.new(
          base_url: "https://rubyskills.org",
          token: "rsk_secret",
          http: http
        )
        allow(RubySkills::Registry::Client).to receive(:new).and_return(client)

        expect {
          described_class.start(["whoami", "--json"])
        }.to output(
          "#{JSON.generate("username" => "johndoe", "email" => "johen@doe.com")}\n"
        ).to_stdout
      end
    end

    it "asks the user to log in when no token is stored" do
      with_user_config_home do
        expect {
          expect {
            described_class.start(["whoami"])
          }.to output(
            a_string_including("Not logged in.", "ruby-skills login")
          ).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
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
        RubySkills::LegacyLockfile.new(
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
        RubySkills::LegacyLockfile.new(
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
                "ruby-skills login"
              )
            ).to_stdout
          }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end
      end
    end
  end

  describe "install" do
    def seed_skill(root, version: "1.4.2")
      skill = root.join("request-specs")
      RubySkills::Generators::Skill.new(root: root).create("rails/request-specs")
      skill.join("references", "http.md").write("# http\n")
      yaml = YAML.safe_load(skill.join("skill.yml").read)
      yaml["version"] = version
      skill.join("skill.yml").write(YAML.dump(yaml))
      skill
    end

    def stub_registry_client(http)
      client = RubySkills::Registry::Client.new(
        base_url: "https://rubyskills.org",
        token: nil,
        http: http
      )
      allow(RubySkills::Registry::Client).to receive(:new).and_return(client)
    end

    def stub_published_skill(http, root)
      skill = seed_skill(root)
      published = RubySkills::Artifact::Builder.new(
        root: skill,
        manifest: RubySkills::Manifest.load(skill),
        destination: root.join("pkg")
      ).build
      checksum = published.checksum
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
          "versions" => ["1.4.2"]
        }
      )
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs/versions/1.4.2",
        status: 200,
        body: {
          "name" => "rails/request-specs",
          "version" => "1.4.2",
          "checksum" => checksum,
          "manifest" => {},
          "published_at" => "2026-08-25T00:00:00Z",
          "yanked" => false,
          "download_url" => "https://rubyskills.org/api/v1/skills/rails/request-specs/versions/1.4.2/download"
        }
      )
      http.stub(
        :get,
        "/api/v1/skills/rails/request-specs/versions/1.4.2/download",
        status: 200,
        body: published.path.binread,
        headers: { "X-Ruby-Skills-SHA256" => checksum }
      )
      published
    end

    it "prints the install report and extracts into .ruby-skills" do
      with_tmp_project do |root|
        http = RubySkillsSpec::FakeRegistryHttp.new
        stub_published_skill(http, root)
        stub_registry_client(http)

        expect {
          described_class.start(["install", "rails/request-specs"])
        }.to output(<<~TEXT).to_stdout
          Resolving rails/request-specs...

          Found 1.4.2

          Downloading...
          ✓ checksum verified
          ✓ artifact valid
          ✓ installed

          rails/request-specs 1.4.2 installed
        TEXT

        installed = root.join(".ruby-skills", "rails", "request-specs", "1.4.2")
        expect(installed.join("skill.yml")).to be_file
        expect(installed.join("SKILL.md")).to be_file
        expect(root.join("Skills.lock")).not_to exist
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
          described_class.start(["install", "rails/missing"])
        }.to output(/Error: Skill not found/).to_stdout
      }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end

    it "exits 1 when SKILL is omitted and no Skillfile exists" do
      with_tmp_project do
        expect {
          expect {
            described_class.start(["install"])
          }.to output(/Error:.*Skillfile not found/).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    it "installs Skillfile dependencies and writes Skills.lock" do
      with_tmp_project do |root|
        http = RubySkillsSpec::FakeRegistryHttp.new
        stub_published_skill(http, root)
        stub_registry_client(http)
        root.join("Skillfile").write(<<~RUBY)
          source "https://rubyskills.org"
          skill "rails/request-specs", "~> 1.4.0"
        RUBY

        expect {
          described_class.start(["install"])
        }.to output(
          a_string_including(
            "Reading Skillfile...",
            "Resolving skills...",
            "Fetching rails/request-specs 1.4.2",
            "Installing rails/request-specs 1.4.2",
            "Writing Skills.lock",
            "Installed 1 skill."
          )
        ).to_stdout

        expect(root.join(".ruby-skills", "rails", "request-specs", "1.4.2", "skill.yml")).to be_file
        lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))
        expect(lockfile.find("rails/request-specs").version).to eq(Gem::Version.new("1.4.2"))
      end
    end

    it "does not reinstall when Skills.lock is already satisfied" do
      with_tmp_project do |root|
        http = RubySkillsSpec::FakeRegistryHttp.new
        stub_published_skill(http, root)
        stub_registry_client(http)
        root.join("Skillfile").write(<<~RUBY)
          source "https://rubyskills.org"
          skill "rails/request-specs", "~> 1.4.0"
        RUBY
        expect { described_class.start(["install"]) }.to output(/Installed 1 skill/).to_stdout

        expect {
          described_class.start(["install"])
        }.to output(/All skills are up to date with Skills.lock/).to_stdout
      end
    end

    it "adds the skill to Skillfile only when --save is given" do
      with_tmp_project do |root|
        http = RubySkillsSpec::FakeRegistryHttp.new
        stub_published_skill(http, root)
        stub_registry_client(http)
        skillfile = root.join("Skillfile")
        skillfile.write(<<~RUBY)
          source "https://rubyskills.org"
        RUBY

        expect {
          described_class.start(["install", "rails/request-specs"])
        }.to output(%r{rails/request-specs 1.4.2 installed}).to_stdout
        expect(skillfile.read).not_to include("rails/request-specs")
        expect(root.join("Skills.lock")).not_to exist

        expect {
          described_class.start(["install", "rails/request-specs", "--save"])
        }.to output(/Writing Skills.lock/).to_stdout

        expect(skillfile.read).to include('skill "rails/request-specs"')
        expect(RubySkills::Lockfile.load(root.join("Skills.lock")).locked?("rails/request-specs"))
          .to be true
      end
    end
  end

  describe "update" do
    def stub_registry_client(http)
      client = RubySkills::Registry::Client.new(
        base_url: "https://rubyskills.org",
        token: nil,
        http: http
      )
      allow(RubySkills::Registry::Client).to receive(:new).and_return(client)
    end

    def publish_versions(http, root, name:, versions:)
      artifacts = versions.to_h { |version|
        namespace, skill = name.split("/", 2)
        dir = root.join("src", namespace, skill, version)
        FileUtils.mkdir_p(dir)
        RubySkills::Generators::Skill.new(root: dir).create(name, in_place: true)
        yaml = YAML.safe_load(dir.join("skill.yml").read)
        yaml["version"] = version
        dir.join("skill.yml").write(YAML.dump(yaml))
        artifact = RubySkills::Artifact::Builder.new(
          root: dir,
          manifest: RubySkills::Manifest.load(dir),
          destination: root.join("pkg", skill, version)
        ).build
        [version, artifact]
      }
      namespace, skill = name.split("/", 2)
      http.stub(
        :get,
        "/api/v1/skills/#{namespace}/#{skill}",
        status: 200,
        body: {
          "name" => name,
          "summary" => name,
          "latest_version" => versions.last,
          "downloads" => 1,
          "categories" => [],
          "versions" => versions
        }
      )
      artifacts.each do |version, artifact|
        http.stub(
          :get,
          "/api/v1/skills/#{namespace}/#{skill}/versions/#{version}",
          status: 200,
          body: {
            "name" => name,
            "version" => version,
            "checksum" => artifact.checksum,
            "manifest" => {},
            "published_at" => "2026-08-01T00:00:00Z",
            "yanked" => false,
            "download_url" =>
              "https://rubyskills.org/api/v1/skills/#{name}/versions/#{version}/download"
          }
        )
        http.stub(
          :get,
          "/api/v1/skills/#{namespace}/#{skill}/versions/#{version}/download",
          status: 200,
          body: artifact.path.binread,
          headers: { "X-Ruby-Skills-SHA256" => artifact.checksum }
        )
      end
      artifacts
    end

    def write_conventions_project(root, artifacts, version:)
      root.join("Skillfile").write(<<~RUBY)
        source "https://rubyskills.org"
        skill "rails/conventions", "~> 1.0"
      RUBY
      RubySkills::Lockfile.new(
        source: "https://rubyskills.org",
        skills: [
          RubySkills::LockedSkill.new(
            name: "rails/conventions",
            version: version,
            checksum: "sha256:#{artifacts.fetch(version).checksum}"
          )
        ],
        dependencies: [
          RubySkills::Dependency.new(
            name: "rails/conventions",
            requirement: Gem::Requirement.new("~> 1.0")
          )
        ]
      ).write(root.join("Skills.lock"))
    end

    it "updates a named Skillfile dependency and rewrites Skills.lock" do
      with_tmp_project do |root|
        http = RubySkillsSpec::FakeRegistryHttp.new
        artifacts = publish_versions(
          http,
          root,
          name: "rails/conventions",
          versions: %w[1.3.2 1.3.5]
        )
        stub_registry_client(http)
        write_conventions_project(root, artifacts, version: "1.3.2")

        expect {
          described_class.start(["update", "rails/conventions"])
        }.to output(<<~TEXT).to_stdout
          Updating rails/conventions...

          1.3.2 -> 1.3.5

          ✓ downloaded
          ✓ checksum verified
          ✓ installed
          ✓ Skills.lock updated
        TEXT

        lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))
        expect(lockfile.find("rails/conventions").version).to eq(Gem::Version.new("1.3.5"))
      end
    end

    it "says when the named skill is already at the newest compatible version" do
      with_tmp_project do |root|
        http = RubySkillsSpec::FakeRegistryHttp.new
        artifacts = publish_versions(
          http,
          root,
          name: "rails/conventions",
          versions: %w[1.3.5]
        )
        stub_registry_client(http)
        write_conventions_project(root, artifacts, version: "1.3.5")

        expect {
          described_class.start(["update", "rails/conventions"])
        }.to output("rails/conventions is already at the newest compatible version.\n").to_stdout
      end
    end

    it "exits 1 when no Skillfile exists" do
      with_tmp_project do
        expect {
          expect {
            described_class.start(["update"])
          }.to output(/Error:.*Skillfile not found/).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end
  end

  describe "outdated" do
    def stub_catalog
      client = RubySkillsSpec::CatalogClient.new
      yield client
      allow(RubySkills::Registry::Client).to receive(:new).and_return(client)
      client
    end

    def write_outdated_project(root)
      root.join("Skillfile").write(<<~RUBY)
        source "https://rubyskills.org"

        skill "rails/conventions", "~> 1.0"
        skill "rails/request-specs", "~> 2.1.0"
        skill "ruby/gem-development", "~> 0.4.0"
      RUBY
      RubySkills::Lockfile.new(
        source: "https://rubyskills.org",
        skills: [
          RubySkills::LockedSkill.new(
            name: "rails/conventions",
            version: "1.2.0",
            checksum: "sha256:#{Digest::SHA256.hexdigest("rails/conventions@1.2.0")}"
          ),
          RubySkills::LockedSkill.new(
            name: "rails/request-specs",
            version: "2.1.4",
            checksum: "sha256:#{Digest::SHA256.hexdigest("rails/request-specs@2.1.4")}"
          ),
          RubySkills::LockedSkill.new(
            name: "ruby/gem-development",
            version: "0.4.1",
            checksum: "sha256:#{Digest::SHA256.hexdigest("ruby/gem-development@0.4.1")}"
          )
        ],
        dependencies: [
          RubySkills::Dependency.new(
            name: "rails/conventions",
            requirement: Gem::Requirement.new("~> 1.0")
          ),
          RubySkills::Dependency.new(
            name: "rails/request-specs",
            requirement: Gem::Requirement.new("~> 2.1.0")
          ),
          RubySkills::Dependency.new(
            name: "ruby/gem-development",
            requirement: Gem::Requirement.new("~> 0.4.0")
          )
        ]
      ).write(root.join("Skills.lock"))
    end

    def stub_example_catalog
      stub_catalog { |registry|
        registry.add("rails/conventions", "1.2.0")
        registry.add("rails/conventions", "1.4.3")
        registry.add("rails/conventions", "2.0.0")
        registry.add("rails/request-specs", "2.1.4")
        registry.add("rails/request-specs", "2.2.0")
        registry.add("ruby/gem-development", "0.4.1")
      }
    end

    it "prints a table of current, allowed, and latest versions" do
      with_tmp_project do |root|
        write_outdated_project(root)
        stub_example_catalog

        expect {
          expect {
            described_class.start(["outdated"])
          }.to output(
            a_string_including(
              "Skill",
              "Current",
              "Allowed",
              "Latest",
              "Status",
              "rails/conventions",
              "1.2.0",
              "1.4.3",
              "2.0.0",
              "update available",
              "rails/request-specs",
              "constrained",
              "ruby/gem-development",
              "current"
            )
          ).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }

        expect(root.join("Skillfile").read).to include("rails/conventions")
        expect(RubySkills::Lockfile.load(root.join("Skills.lock")).find("rails/conventions").version)
          .to eq(Gem::Version.new("1.2.0"))
      end
    end

    it "prints JSON when --json is given" do
      with_tmp_project do |root|
        write_outdated_project(root)
        stub_example_catalog

        expect {
          expect {
            described_class.start(["outdated", "--json"])
          }.to output(
            "#{JSON.generate(
              [
                {
                  "name" => "rails/conventions",
                  "current" => "1.2.0",
                  "allowed" => "1.4.3",
                  "latest" => "2.0.0",
                  "status" => "update_available"
                },
                {
                  "name" => "rails/request-specs",
                  "current" => "2.1.4",
                  "allowed" => "2.1.4",
                  "latest" => "2.2.0",
                  "status" => "constrained"
                },
                {
                  "name" => "ruby/gem-development",
                  "current" => "0.4.1",
                  "allowed" => "0.4.1",
                  "latest" => "0.4.1",
                  "status" => "current"
                }
              ]
            )}\n"
          ).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    it "limits output to one Skillfile dependency" do
      with_tmp_project do |root|
        write_outdated_project(root)
        stub_example_catalog

        expect {
          expect {
            described_class.start(["outdated", "rails/conventions"])
          }.to output(
            a_string_including(
              "rails/conventions",
              "1.2.0",
              "1.4.3",
              "2.0.0",
              "update available"
            )
          ).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    it "exits 0 when every listed skill is current" do
      with_tmp_project do |root|
        root.join("Skillfile").write(<<~RUBY)
          source "https://rubyskills.org"
          skill "ruby/gem-development", "~> 0.4.0"
        RUBY
        RubySkills::Lockfile.new(
          source: "https://rubyskills.org",
          skills: [
            RubySkills::LockedSkill.new(
              name: "ruby/gem-development",
              version: "0.4.1",
              checksum: "sha256:#{Digest::SHA256.hexdigest("ruby/gem-development@0.4.1")}"
            )
          ],
          dependencies: [
            RubySkills::Dependency.new(
              name: "ruby/gem-development",
              requirement: Gem::Requirement.new("~> 0.4.0")
            )
          ]
        ).write(root.join("Skills.lock"))
        stub_catalog do |registry|
          registry.add("ruby/gem-development", "0.4.1")
        end

        expect {
          described_class.start(["outdated"])
        }.to output(a_string_including("ruby/gem-development", "current")).to_stdout
      end
    end

    it "exits 2 when Skillfile is missing" do
      with_tmp_project do
        expect {
          expect {
            described_class.start(["outdated"])
          }.to output(/Error:.*Skillfile not found/).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
      end
    end

    it "exits 2 when the named skill is not in the Skillfile" do
      with_tmp_project do |root|
        write_outdated_project(root)
        stub_example_catalog

        expect {
          expect {
            described_class.start(["outdated", "rails/security"])
          }.to output(%r{Error:.*rails/security.*Skillfile}).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
      end
    end
  end

  describe "remove" do
    def config_for(root)
      RubySkills::Config.new(root: root)
    end

    def plant_installed(root, name, version)
      path = RubySkills::Install.destination(name, version, config: config_for(root))
      FileUtils.mkdir_p(path)
      path.join("SKILL.md").write("# #{name}\n")
      path
    end

    def write_lock(root, entries)
      RubySkills::Lockfile.new(
        source: "https://rubyskills.org",
        skills: entries.map { |name, version, _requirement|
          RubySkills::LockedSkill.new(
            name: name,
            version: version,
            checksum: "sha256:#{Digest::SHA256.hexdigest("#{name}@#{version}")}"
          )
        },
        dependencies: entries.map { |name, _version, requirement|
          RubySkills::Dependency.new(
            name: name,
            requirement: Gem::Requirement.new(requirement)
          )
        }
      ).write(root.join("Skills.lock"))
    end

    def stub_catalog(*releases)
      client = RubySkillsSpec::CatalogClient.new
      releases.each do |name, version|
        client.add(name, version)
      end
      allow(RubySkills::Registry::Client).to receive(:new).and_return(client)
    end

    it "removes an installed skill without changing Skillfile or Skills.lock" do
      with_tmp_project do |root|
        skillfile = root.join("Skillfile")
        skillfile.write(<<~RUBY)
          source "https://rubyskills.org"

          skill "demo/a", "~> 1.0"
        RUBY
        write_lock(root, [["demo/a", "1.0.0", "~> 1.0"]])
        planted = plant_installed(root, "demo/a", "1.0.0")
        original_skillfile = skillfile.read
        original_lock = root.join("Skills.lock").read

        expect {
          described_class.start(["remove", "demo/a"])
        }.to output(/✓ removed/).to_stdout

        expect(planted).not_to exist
        expect(skillfile.read).to eq(original_skillfile)
        expect(root.join("Skills.lock").read).to eq(original_lock)
      end
    end

    it "prints a message and exits successfully when the skill is not installed" do
      with_tmp_project do
        expect {
          described_class.start(["remove", "demo/a"])
        }.to output("demo/a is not installed.\n").to_stdout
      end
    end

    it "warns when Skills.lock still references the removed skill" do
      with_tmp_project do |root|
        root.join("Skillfile").write(<<~RUBY)
          source "https://rubyskills.org"

          skill "demo/a", "~> 1.0"
        RUBY
        write_lock(root, [["demo/a", "1.0.0", "~> 1.0"]])
        plant_installed(root, "demo/a", "1.0.0")

        expect {
          described_class.start(["remove", "demo/a"])
        }.to output(/still referenced by this project's Skills.lock/).to_stdout
      end
    end

    it "removes A from Skillfile, lock, and storage while leaving B" do
      with_tmp_project do |root|
        root.join("Skillfile").write(<<~RUBY)
          source "https://rubyskills.org"

          skill "demo/a", "~> 1.0"
          skill "demo/b", "~> 2.0"
        RUBY
        write_lock(root, [["demo/a", "1.0.0", "~> 1.0"], ["demo/b", "2.0.0", "~> 2.0"]])
        plant_installed(root, "demo/a", "1.0.0")
        plant_installed(root, "demo/b", "2.0.0")
        stub_catalog(["demo/b", "2.0.0"])

        expect {
          described_class.start(["remove", "demo/a", "--save"])
        }.to output(%r{Removed demo/a}).to_stdout

        expect(root.join("Skillfile").read).to eq(<<~RUBY)
          source "https://rubyskills.org"

          skill "demo/b", "~> 2.0"
        RUBY
        lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))
        expect(lockfile.locked?("demo/a")).to be false
        expect(lockfile.find("demo/b").version).to eq(Gem::Version.new("2.0.0"))
        expect(RubySkills::Install.installed?("demo/a", "1.0.0", config: config_for(root)))
          .to be false
        expect(RubySkills::Install.installed?("demo/b", "2.0.0", config: config_for(root)))
          .to be true
      end
    end

    it "exits 1 when --save names a skill that is not declared" do
      with_tmp_project do |root|
        root.join("Skillfile").write('skill "demo/b"')

        expect {
          expect {
            described_class.start(["remove", "demo/a", "--save"])
          }.to output("demo/a is not declared in Skillfile.\n").to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end

    it "exits 1 when --save cannot find a Skillfile" do
      with_tmp_project do
        expect {
          expect {
            described_class.start(["remove", "demo/a", "--save"])
          }.to output(/Error:.*Skillfile not found/).to_stdout
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end
  end
end
