# frozen_string_literal: true

require "yaml"

RSpec.describe RubySkills::Updater do
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

  def publish(http, root, name:, versions:)
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
      stub_version(http, name, version, artifact)
    end
    artifacts
  end

  def stub_version(http, name, version, artifact)
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

  def client_for(http)
    RubySkills::Registry::Client.new(
      base_url: "https://rubyskills.org",
      token: nil,
      http: http
    )
  end

  def write_skillfile(root)
    root.join("Skillfile").write(<<~RUBY)
      source "https://rubyskills.org"

      skill "rails/conventions", "~> 1.0"
      skill "rails/request-specs", "~> 2.1.0"
    RUBY
  end

  def write_lock(root, artifacts, conventions:, request_specs:)
    RubySkills::Lockfile.new(
      source: "https://rubyskills.org",
      skills: [
        RubySkills::LockedSkill.new(
          name: "rails/conventions",
          version: conventions,
          checksum: "sha256:#{artifacts.dig("rails/conventions", conventions).checksum}"
        ),
        RubySkills::LockedSkill.new(
          name: "rails/request-specs",
          version: request_specs,
          checksum: "sha256:#{artifacts.dig("rails/request-specs", request_specs).checksum}"
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
        )
      ]
    ).write(root.join("Skills.lock"))
  end

  def seed_project(http, root)
    artifacts = {
      "rails/conventions" => publish(
        http,
        root,
        name: "rails/conventions",
        versions: %w[1.3.2 1.3.5 2.0.0]
      ),
      "rails/request-specs" => publish(
        http,
        root,
        name: "rails/request-specs",
        versions: %w[2.1.4 2.2.0]
      )
    }
    write_skillfile(root)
    write_lock(root, artifacts, conventions: "1.3.2", request_specs: "2.1.4")
    artifacts
  end

  def lock_one(root, name:, version:, checksum:, requirement:)
    RubySkills::Lockfile.new(
      source: "https://rubyskills.org",
      skills: [
        RubySkills::LockedSkill.new(name: name, version: version, checksum: checksum)
      ],
      dependencies: [
        RubySkills::Dependency.new(name: name, requirement: Gem::Requirement.new(requirement))
      ]
    ).write(root.join("Skills.lock"))
  end

  def stub_mismatched_conventions(http, root)
    artifact = build_artifact(
      seed_skill(root, name: "rails/conventions", version: "1.3.5"),
      destination: root.join("pkg")
    )
    http.stub(
      :get,
      "/api/v1/skills/rails/conventions",
      status: 200,
      body: {
        "name" => "rails/conventions",
        "summary" => "conventions",
        "latest_version" => "1.3.5",
        "downloads" => 1,
        "categories" => [],
        "versions" => %w[1.3.2 1.3.5]
      }
    )
    http.stub(
      :get,
      "/api/v1/skills/rails/conventions/versions/1.3.5",
      status: 200,
      body: {
        "name" => "rails/conventions",
        "version" => "1.3.5",
        "checksum" => "a" * 64,
        "manifest" => {},
        "published_at" => "2026-08-01T00:00:00Z",
        "yanked" => false,
        "download_url" =>
          "https://rubyskills.org/api/v1/skills/rails/conventions/versions/1.3.5/download"
      }
    )
    http.stub(
      :get,
      "/api/v1/skills/rails/conventions/versions/1.3.5/download",
      status: 200,
      body: artifact.path.binread,
      headers: { "X-Ruby-Skills-SHA256" => artifact.checksum }
    )
  end

  def updater(root, http, output: StringIO.new)
    described_class.new(
      client: client_for(http),
      starting_directory: root,
      output: output
    )
  end

  it "updates every skill to the newest version allowed by the Skillfile" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      seed_project(http, root)
      output = StringIO.new

      updater(root, http, output: output).update

      lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))
      expect(lockfile.find("rails/conventions").version).to eq(Gem::Version.new("1.3.5"))
      expect(lockfile.find("rails/request-specs").version).to eq(Gem::Version.new("2.1.4"))
      expect(root.join(".ruby-skills", "rails", "conventions", "1.3.5")).to be_directory
      expect(root.join(".ruby-skills", "rails", "request-specs", "2.2.0")).not_to exist
      expect(output.string).to include("1.3.2 -> 1.3.5", "✓ Skills.lock updated")
      expect(output.string).not_to include("2.1.4 -> 2.2.0")
    end
  end

  it "updates only the named skill and keeps every other lock pin" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      seed_project(http, root)
      output = StringIO.new

      expect(updater(root, http, output: output).update("rails/conventions")).to be_a(
        RubySkills::Resolution
      )

      lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))
      expect(lockfile.find("rails/conventions").version).to eq(Gem::Version.new("1.3.5"))
      expect(lockfile.find("rails/request-specs").version).to eq(Gem::Version.new("2.1.4"))
      expect(output.string).to eq(<<~TEXT)
        Updating rails/conventions...

        1.3.2 -> 1.3.5

        ✓ downloaded
        ✓ checksum verified
        ✓ installed
        ✓ Skills.lock updated
      TEXT
    end
  end

  it "does not rewrite the lock when the named skill is already newest" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      artifacts = seed_project(http, root)
      write_lock(root, artifacts, conventions: "1.3.5", request_specs: "2.1.4")
      before = root.join("Skills.lock").read
      output = StringIO.new

      updater(root, http, output: output).update("rails/conventions")

      expect(output.string).to eq(
        "rails/conventions is already at the newest compatible version.\n"
      )
      expect(root.join("Skills.lock").read).to eq(before)
      expect(root.join(".ruby-skills", "rails", "conventions", "1.3.5")).not_to exist
    end
  end

  it "reports when every skill is already at the newest compatible version" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      artifacts = seed_project(http, root)
      write_lock(root, artifacts, conventions: "1.3.5", request_specs: "2.1.4")
      output = StringIO.new

      updater(root, http, output: output).update

      expect(output.string).to eq(
        "All skills are already at the newest compatible versions.\n"
      )
    end
  end

  it "does not write Skills.lock when a checksum does not match" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      stub_mismatched_conventions(http, root)
      root.join("Skillfile").write(<<~RUBY)
        source "https://rubyskills.org"
        skill "rails/conventions", "~> 1.0"
      RUBY
      lock_one(
        root,
        name: "rails/conventions",
        version: "1.3.2",
        checksum: "sha256:#{"b" * 64}",
        requirement: "~> 1.0"
      )
      before = root.join("Skills.lock").read

      expect {
        updater(root, http).update("rails/conventions")
      }.to raise_error(RubySkills::Error, "Checksum mismatch")
      expect(root.join("Skills.lock").read).to eq(before)
      expect(root.join(".ruby-skills")).not_to exist
    end
  end

  it "raises when the named skill is not in the Skillfile" do
    with_tmp_project do |root|
      http = RubySkillsSpec::FakeRegistryHttp.new
      seed_project(http, root)

      expect {
        updater(root, http).update("rails/missing")
      }.to raise_error(RubySkills::Error, "Skill `rails/missing` is not in the Skillfile")
    end
  end
end
