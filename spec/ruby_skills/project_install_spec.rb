# frozen_string_literal: true

require "digest"
require "yaml"

RSpec.describe RubySkills::ProjectInstall do
  def seed_skill(root, name:, version:)
    namespace, skill = name.split("/", 2)
    dir = root.join("src", namespace, skill, version)
    FileUtils.mkdir_p(dir)
    RubySkills::Generators::Skill.new(root: dir).create(name, in_place: true)
    yaml = YAML.safe_load(dir.join("skill.yml").read)
    yaml["version"] = version
    dir.join("skill.yml").write(YAML.dump(yaml))
    dir
  end

  def build_artifact(skill, destination:)
    RubySkills::Artifact::Builder.new(
      root: skill,
      manifest: RubySkills::Manifest.load(skill),
      destination: destination
    ).build
  end

  def publish(http, root, name:, versions:, dependencies: {})
    artifacts = versions.to_h { |version|
      artifact = build_artifact(
        seed_skill(root, name: name, version: version),
        destination: root.join("pkg", name.tr("/", "-"), version)
      )
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
        "latest_version" => versions.max_by { |value| Gem::Version.new(value) },
        "downloads" => 1,
        "categories" => [],
        "versions" => versions
      }
    )
    artifacts.each do |version, artifact|
      stub_version(
        http, name, version, artifact,
        dependencies: dependencies[version] || []
      )
    end
    artifacts
  end

  def stub_version(http, name, version, artifact, dependencies: [])
    namespace, skill = name.split("/", 2)
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
          "https://rubyskills.org/api/v1/skills/#{namespace}/#{skill}/versions/#{version}/download",
        "dependencies" => dependencies.map { |dep_name, requirement|
          { "name" => dep_name, "requirement" => requirement }
        }
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

  def client_for(http)
    RubySkills::Registry::Client.new(
      base_url: "https://rubyskills.org",
      token: nil,
      http: http
    )
  end

  def stub_checksum_mismatch(http, root, name:, version:)
    artifact = build_artifact(
      seed_skill(root, name: name, version: version),
      destination: root.join("pkg")
    )
    namespace, skill = name.split("/", 2)
    http.stub(
      :get,
      "/api/v1/skills/#{namespace}/#{skill}",
      status: 200,
      body: {
        "name" => name,
        "summary" => name,
        "latest_version" => version,
        "downloads" => 1,
        "categories" => [],
        "versions" => [version]
      }
    )
    http.stub(
      :get,
      "/api/v1/skills/#{namespace}/#{skill}/versions/#{version}",
      status: 200,
      body: {
        "name" => name,
        "version" => version,
        "checksum" => "a" * 64,
        "manifest" => {},
        "published_at" => "2026-08-01T00:00:00Z",
        "yanked" => false,
        "download_url" =>
          "https://rubyskills.org/api/v1/skills/#{namespace}/#{skill}/versions/#{version}/download"
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

  def write_skillfile(root, contents)
    root.join("Skillfile").write(contents)
  end

  def install(root, http, save: nil, output: StringIO.new)
    described_class.new(
      save: save,
      client: client_for(http),
      starting_directory: root,
      output: output
    ).run
    output.string
  end

  it "resolves, installs, and writes Skills.lock" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      conventions = publish(http, root, name: "rails/conventions", versions: %w[1.3.2 2.0.0])
      request_specs = publish(
        http,
        root,
        name: "rails/request-specs",
        versions: %w[2.1.4 2.2.0]
      )
      write_skillfile(
        root,
        <<~RUBY
          source "https://rubyskills.org"

          skill "rails/conventions", "~> 1.0"
          skill "rails/request-specs", "~> 2.1.0"
        RUBY
      )

      output = install(root, http)

      expect(output).to include(
        "Reading Skillfile...",
        "Resolving skills...",
        "Fetching rails/conventions 1.3.2",
        "Fetching rails/request-specs 2.1.4",
        "Installing rails/conventions 1.3.2",
        "Installing rails/request-specs 2.1.4",
        "Writing Skills.lock",
        "Installed 2 skills."
      )
      expect(root.join(".ruby-skills", "rails", "conventions", "1.3.2", "skill.yml")).to be_file
      expect(root.join(".ruby-skills", "rails", "request-specs", "2.1.4", "skill.yml")).to be_file
      lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))
      expect(lockfile.find("rails/conventions").version).to eq(Gem::Version.new("1.3.2"))
      expect(lockfile.find("rails/conventions").checksum).to eq(
        "sha256:#{conventions.fetch("1.3.2").checksum}"
      )
      expect(lockfile.find("rails/request-specs").checksum).to eq(
        "sha256:#{request_specs.fetch("2.1.4").checksum}"
      )
    end
  end

  it "keeps a locked version during install when a newer release exists" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      artifacts = publish(http, root, name: "rails/conventions", versions: %w[1.3.2 1.3.3])
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"
        skill "rails/conventions", "~> 1.0"
      RUBY
      RubySkills::Lockfile.new(
        source: "https://rubyskills.org",
        skills: [
          RubySkills::LockedSkill.new(
            name: "rails/conventions",
            version: "1.3.2",
            checksum: "sha256:#{artifacts.fetch("1.3.2").checksum}"
          )
        ],
        dependencies: [
          RubySkills::Dependency.new(
            name: "rails/conventions",
            requirement: Gem::Requirement.new("~> 1.0")
          )
        ]
      ).write(root.join("Skills.lock"))

      install(root, http)

      lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))
      expect(lockfile.find("rails/conventions").version).to eq(Gem::Version.new("1.3.2"))
      expect(root.join(".ruby-skills", "rails", "conventions", "1.3.3")).not_to exist
      expect(root.join(".ruby-skills", "rails", "conventions", "1.3.2")).to be_directory
    end
  end

  it "uses already installed skills and fetches the rest" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      publish(http, root, name: "rails/conventions", versions: %w[1.3.2])
      publish(http, root, name: "rails/request-specs", versions: %w[2.1.4])
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"
        skill "rails/conventions", "~> 1.0"
      RUBY
      install(root, http)
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"
        skill "rails/conventions", "~> 1.0"
        skill "rails/request-specs", "~> 2.1.0"
      RUBY

      output = install(root, http)

      expect(output).to include(
        "Using rails/conventions 1.3.2",
        "Fetching rails/request-specs 2.1.4",
        "Installing rails/request-specs 2.1.4"
      )
    end
  end

  it "reports when every locked skill is already installed" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      publish(http, root, name: "rails/conventions", versions: %w[1.3.2])
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"
        skill "rails/conventions", "~> 1.0"
      RUBY
      described_class.new(
        client: client_for(http),
        starting_directory: root,
        output: StringIO.new
      ).run

      output = install(root, http)

      expect(output).to include("All skills are up to date with Skills.lock.")
      expect(output).not_to include("Fetching")
    end
  end

  it "does not write Skills.lock when a checksum does not match" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      stub_checksum_mismatch(http, root, name: "rails/conventions", version: "1.3.2")
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"
        skill "rails/conventions", "~> 1.0"
      RUBY

      expect {
        install(root, http)
      }.to raise_error(RubySkills::Error, "Checksum mismatch")
      expect(root.join("Skills.lock")).not_to exist
      expect(root.join(".ruby-skills")).not_to exist
    end
  end

  it "adds a Skillfile dependency when save is given" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      publish(http, root, name: "rails/request-specs", versions: %w[2.1.4])
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"
      RUBY

      install(root, http, save: "rails/request-specs")

      skillfile = RubySkills::Skillfile.load(root.join("Skillfile"))
      expect(skillfile).to include("rails/request-specs")
      expect(root.join("Skillfile").read).to include('skill "rails/request-specs"')
      expect(root.join(".ruby-skills", "rails", "request-specs", "2.1.4")).to be_directory
      expect(RubySkills::Lockfile.load(root.join("Skills.lock")).locked?("rails/request-specs"))
        .to be true
    end
  end

  it "installs transitive dependencies and records them under their parents" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      conventions = publish(
        http, root, name: "rails/conventions", versions: %w[1.4.0 1.5.0 1.8.0 2.0.0]
      )
      publish(
        http,
        root,
        name: "rails/request-specs",
        versions: %w[2.1.0],
        dependencies: { "2.1.0" => [["rails/conventions", ">= 1.5"]] }
      )
      publish(
        http,
        root,
        name: "rails/security",
        versions: %w[1.3.0],
        dependencies: { "1.3.0" => [["rails/conventions", "~> 1.0"]] }
      )
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"
        skill "rails/request-specs", "~> 2.0"
        skill "rails/security", "~> 1.0"
      RUBY

      install(root, http)
      lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))

      expect(lockfile.find("rails/conventions").version).to eq(Gem::Version.new("1.8.0"))
      expect(lockfile.dependencies.map(&:name)).to eq(
        ["rails/request-specs", "rails/security"]
      )
      expect(lockfile.find("rails/request-specs").dependencies).to eq(
        [
          RubySkills::Dependency.new(
            name: "rails/conventions",
            requirement: Gem::Requirement.new(">= 1.5")
          )
        ]
      )
      expect(root.join(".ruby-skills", "rails", "conventions", "1.8.0")).to be_directory
      expect(lockfile.serialize).to include("sha256: #{conventions.fetch("1.8.0").checksum}")
    end
  end

  it "does not write Skills.lock when requirements conflict" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      publish(http, root, name: "ruby/foo", versions: %w[1.5.0 2.0.0])
      publish(
        http,
        root,
        name: "ruby/a",
        versions: %w[1.0.0],
        dependencies: { "1.0.0" => [["ruby/foo", "~> 1.0"]] }
      )
      publish(
        http,
        root,
        name: "ruby/b",
        versions: %w[1.0.0],
        dependencies: { "1.0.0" => [["ruby/foo", ">= 2.0"]] }
      )
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"
        skill "ruby/a", "~> 1.0"
        skill "ruby/b", "~> 1.0"
      RUBY

      expect { install(root, http) }.to raise_error(RubySkills::Resolver::VersionConflict)
      expect(root.join("Skills.lock")).not_to exist
      expect(root.join(".ruby-skills")).not_to exist
    end
  end
end
