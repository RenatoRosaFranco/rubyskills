# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::Resolver do
  def sha(name, version)
    Digest::SHA256.hexdigest("#{name}@#{version}")
  end

  def checksum(name, version)
    "sha256:#{sha(name, version)}"
  end

  def dep(name, requirement)
    RubySkills::Dependency.new(name: name, requirement: Gem::Requirement.new(requirement))
  end

  def skillfile_with(*dependencies)
    RubySkills::Skillfile.new(
      path: "Skillfile",
      source: "https://rubyskills.org",
      dependencies: dependencies
    )
  end

  def locked(name, version)
    RubySkills::LockedSkill.new(
      name: name,
      version: version,
      checksum: checksum(name, version)
    )
  end

  def lockfile_with(*skills)
    RubySkills::Lockfile.new(
      source: "https://rubyskills.org",
      skills: skills,
      dependencies: skills.map { |skill| dep(skill.name, ">= 0") }
    )
  end

  def catalog
    client = RubySkillsSpec::CatalogClient.new
    yield client
    client
  end

  def resolve(skillfile, client:, lockfile: nil, update: false)
    described_class.new(
      skillfile: skillfile,
      client: client,
      lockfile: lockfile,
      update: update
    ).resolve
  end

  describe "initial resolution" do
    it "picks the highest compatible published version for each skill" do
      client = catalog { |registry|
        registry.add("rails/conventions", "1.0.0")
        registry.add("rails/conventions", "1.2.0")
        registry.add("rails/conventions", "1.3.2")
        registry.add("rails/conventions", "2.0.0")
        registry.add("rails/request-specs", "2.1.0")
        registry.add("rails/request-specs", "2.1.4")
        registry.add("rails/request-specs", "2.2.0")
      }

      resolution = resolve(
        skillfile_with(
          dep("rails/conventions", "~> 1.0"),
          dep("rails/request-specs", "~> 2.1.0")
        ),
        client: client
      )

      conventions = resolution.find("rails/conventions")
      request_specs = resolution.find("rails/request-specs")

      expect(conventions.version).to eq(Gem::Version.new("1.3.2"))
      expect(conventions.checksum).to eq(checksum("rails/conventions", "1.3.2"))
      expect(conventions.download_url).to include("/rails/conventions/versions/1.3.2/download")
      expect(conventions.source).to eq("https://rubyskills.org")
      expect(request_specs.version).to eq(Gem::Version.new("2.1.4"))
      expect(request_specs.checksum).to eq(checksum("rails/request-specs", "2.1.4"))
    end
  end

  describe "locked versions" do
    it "preserves a locked version that still satisfies the Skillfile" do
      client = catalog { |registry|
        registry.add("rails/conventions", "1.3.2")
        registry.add("rails/conventions", "1.3.3")
      }

      resolution = resolve(
        skillfile_with(dep("rails/conventions", "~> 1.0")),
        client: client,
        lockfile: lockfile_with(locked("rails/conventions", "1.3.2"))
      )

      expect(resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.3.2"))
    end

    it "does not treat install as update when a newer compatible version exists" do
      client = catalog { |registry|
        registry.add("rails/conventions", "1.3.2")
        registry.add("rails/conventions", "1.3.3")
      }

      skillfile = skillfile_with(dep("rails/conventions", "~> 1.0"))
      lockfile = lockfile_with(locked("rails/conventions", "1.3.2"))

      installed = resolve(skillfile, client: client, lockfile: lockfile)
      updated = resolve(skillfile, client: client, lockfile: lockfile, update: true)

      expect(installed.find("rails/conventions").version).to eq(Gem::Version.new("1.3.2"))
      expect(updated.find("rails/conventions").version).to eq(Gem::Version.new("1.3.3"))
    end

    it "updates only the named skill when update is a skill identifier" do
      client = catalog { |registry|
        registry.add("rails/conventions", "1.3.2")
        registry.add("rails/conventions", "1.3.5")
        registry.add("rails/request-specs", "2.1.4")
        registry.add("rails/request-specs", "2.1.8")
      }
      skillfile = skillfile_with(
        dep("rails/conventions", "~> 1.0"),
        dep("rails/request-specs", "~> 2.1.0")
      )
      lockfile = lockfile_with(
        locked("rails/conventions", "1.3.2"),
        locked("rails/request-specs", "2.1.4")
      )

      resolution = resolve(
        skillfile,
        client: client,
        lockfile: lockfile,
        update: "rails/conventions"
      )

      expect(resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.3.5"))
      expect(resolution.find("rails/request-specs").version).to eq(Gem::Version.new("2.1.4"))
    end

    it "resolves again when the Skillfile requirement no longer matches the lock" do
      client = catalog { |registry|
        registry.add("rails/conventions", "1.3.2")
        registry.add("rails/conventions", "2.0.0")
      }

      resolution = resolve(
        skillfile_with(dep("rails/conventions", "~> 2.0")),
        client: client,
        lockfile: lockfile_with(locked("rails/conventions", "1.3.2"))
      )

      expect(resolution.find("rails/conventions").version).to eq(Gem::Version.new("2.0.0"))
    end

    it "resolves again when the locked version is yanked or missing" do
      yanked = catalog { |registry|
        registry.add("rails/conventions", "1.3.2", yanked: true)
        registry.add("rails/conventions", "1.3.1")
      }
      missing = catalog { |registry| registry.add("rails/conventions", "1.2.0") }

      yanked_resolution = resolve(
        skillfile_with(dep("rails/conventions", "~> 1.0")),
        client: yanked,
        lockfile: lockfile_with(locked("rails/conventions", "1.3.2"))
      )
      missing_resolution = resolve(
        skillfile_with(dep("rails/conventions", "~> 1.0")),
        client: missing,
        lockfile: lockfile_with(locked("rails/conventions", "1.3.2"))
      )

      expect(yanked_resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.3.1"))
      expect(missing_resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.2.0"))
    end
  end

  describe "version selection" do
    it "chooses the highest Gem::Version, not the lexicographic maximum" do
      client = catalog { |registry|
        registry.add("rails/conventions", "1.2.0")
        registry.add("rails/conventions", "1.9.0")
        registry.add("rails/conventions", "1.10.0")
      }

      resolution = resolve(
        skillfile_with(dep("rails/conventions", "~> 1.0")),
        client: client
      )

      expect(resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.10.0"))
    end

    it "ignores yanked and unpublished versions" do
      client = catalog { |registry|
        registry.add("rails/conventions", "1.3.2")
        registry.add("rails/conventions", "1.3.3", yanked: true)
        registry.add("rails/conventions", "1.4.0", published: false)
      }

      resolution = resolve(
        skillfile_with(dep("rails/conventions", "~> 1.0")),
        client: client
      )

      expect(resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.3.2"))
    end
  end

  describe "failures" do
    it "fails when the skill is missing from the registry" do
      expect {
        resolve(
          skillfile_with(dep("rails/missing", "~> 1.0")),
          client: RubySkillsSpec::CatalogClient.new
        )
      }.to raise_error(
        RubySkills::Resolver::Error,
        "Could not find skill rails/missing in the registry"
      )
    end

    it "fails when no published version satisfies the requirement" do
      client = catalog { |registry|
        registry.add("rails/conventions", "1.3.2")
        registry.add("rails/conventions", "2.0.0")
      }

      expect {
        resolve(skillfile_with(dep("rails/conventions", "~> 9.0")), client: client)
      }.to raise_error(
        RubySkills::Resolver::Error,
        "Could not find a version of rails/conventions that satisfies ~> 9.0"
      )
    end

    it "fails when every matching version is yanked or unpublished" do
      client = catalog { |registry|
        registry.add("rails/conventions", "2.0.0", yanked: true)
        registry.add("rails/conventions", "2.1.0", published: false)
        registry.add("rails/conventions", "1.0.0")
      }

      expect {
        resolve(skillfile_with(dep("rails/conventions", "~> 2.0")), client: client)
      }.to raise_error(
        RubySkills::Resolver::Error,
        %r{rails/conventions that satisfies ~> 2.0}
      )
    end
  end
end
