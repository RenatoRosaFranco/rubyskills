# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::Lockfile do
  def sha(seed)
    Digest::SHA256.hexdigest(seed.to_s)
  end

  def checksum(seed)
    "sha256:#{sha(seed)}"
  end

  def locked(name, version, seed = name)
    RubySkills::LockedSkill.new(name: name, version: version, checksum: checksum(seed))
  end

  def dep(name, requirement = ">= 0")
    RubySkills::Dependency.new(name: name, requirement: Gem::Requirement.new(requirement))
  end

  def skillfile_with(*dependencies)
    RubySkills::Skillfile.new(
      path: "Skillfile",
      source: "https://rubyskills.org",
      dependencies: dependencies
    )
  end

  def build_lock(skills:, dependencies:, source: "https://rubyskills.org")
    described_class.new(source: source, skills: skills, dependencies: dependencies)
  end

  def write_lock(root, contents)
    path = root.join("Skills.lock")
    path.write(contents)
    path
  end

  let(:conventions) { locked("rails/conventions", "1.3.2", "conventions") }
  let(:request_specs) { locked("rails/request-specs", "2.1.4", "request-specs") }

  describe "serialization" do
    it "writes skills and dependencies in alphabetical order with a trailing newline" do
      lockfile = build_lock(
        skills: [request_specs, conventions],
        dependencies: [
          dep("rails/request-specs", "~> 2.1"),
          dep("rails/conventions", "~> 1.0")
        ]
      )

      expect(lockfile.serialize).to eq(<<~LOCK)
        RUBY SKILLS
          remote: https://rubyskills.org

          rails/conventions (1.3.2)
            sha256: #{sha("conventions")}

          rails/request-specs (2.1.4)
            sha256: #{sha("request-specs")}

        DEPENDENCIES
          rails/conventions (~> 1.0)
          rails/request-specs (~> 2.1)
      LOCK
    end

    it "is byte-identical for the same resolved state" do
      first = build_lock(
        skills: [request_specs, conventions],
        dependencies: [
          dep("rails/request-specs", "~> 2.1"),
          dep("rails/conventions", "~> 1.0")
        ]
      )
      second = build_lock(
        skills: [conventions, request_specs],
        dependencies: [
          dep("rails/conventions", "~> 1.0"),
          dep("rails/request-specs", "~> 2.1")
        ]
      )

      expect(first.serialize).to eq(second.serialize)
      expect(first.serialize).to end_with("\n")
    end

    it "round-trips parse -> serialize -> parse" do
      with_tmp_project do |root|
        original = build_lock(
          skills: [conventions, request_specs],
          dependencies: [
            dep("rails/conventions", "~> 1.0"),
            dep("rails/request-specs", "~> 2.1")
          ]
        )
        path = root.join("Skills.lock")
        original.write(path)
        loaded = described_class.load(path)

        expect(loaded.source).to eq("https://rubyskills.org")
        expect(loaded.find("rails/conventions").version).to eq(Gem::Version.new("1.3.2"))
        expect(loaded.find("rails/conventions").checksum).to eq(checksum("conventions"))
        expect(loaded.serialize).to eq(original.serialize)
        expect(described_class.load(write_lock(root, loaded.serialize)).serialize).to eq(
          loaded.serialize
        )
      end
    end
  end

  describe ".load" do
    it "parses locked skills as Gem::Version and normalized checksums" do
      with_tmp_project do |root|
        path = write_lock(root, <<~LOCK)
          RUBY SKILLS
            remote: https://rubyskills.org

            rails/conventions (1.3.2)
              sha256: #{sha("conventions").upcase}

          DEPENDENCIES
            rails/conventions (~> 1.0)
        LOCK

        lockfile = described_class.load(path)
        skill = lockfile.find("rails/conventions")

        expect(lockfile.source).to eq("https://rubyskills.org")
        expect(lockfile.locked?("rails/conventions")).to be true
        expect(skill.version).to eq(Gem::Version.new("1.3.2"))
        expect(skill.checksum).to eq(checksum("conventions"))
        expect(lockfile.dependencies.first.requirement).to eq(Gem::Requirement.new("~> 1.0"))
      end
    end

    it "raises when the file is missing" do
      with_tmp_project do |root|
        expect {
          described_class.load(root.join("Skills.lock"))
        }.to raise_error(RubySkills::Lockfile::Error, /Skills.lock not found/)
      end
    end

    it "rejects an invalid version" do
      with_tmp_project do |root|
        expect {
          described_class.load(write_lock(root, <<~LOCK))
            RUBY SKILLS
              remote: https://rubyskills.org

              rails/conventions (not-a-version)
                sha256: #{sha("x")}

            DEPENDENCIES
              rails/conventions (~> 1.0)
          LOCK
        }.to raise_error(RubySkills::Lockfile::Error, /Invalid version/)
      end
    end

    it "rejects a missing checksum" do
      with_tmp_project do |root|
        expect {
          described_class.load(write_lock(root, <<~LOCK))
            RUBY SKILLS
              remote: https://rubyskills.org

              rails/conventions (1.3.2)

            DEPENDENCIES
              rails/conventions (~> 1.0)
          LOCK
        }.to raise_error(RubySkills::Lockfile::Error, /Missing checksum/)
      end
    end

    it "rejects a malformed checksum" do
      with_tmp_project do |root|
        expect {
          described_class.load(write_lock(root, <<~LOCK))
            RUBY SKILLS
              remote: https://rubyskills.org

              rails/conventions (1.3.2)
                sha256: not-sha256

            DEPENDENCIES
              rails/conventions (~> 1.0)
          LOCK
        }.to raise_error(RubySkills::Lockfile::Error, /Malformed checksum/)
      end
    end

    it "rejects a duplicated locked skill" do
      with_tmp_project do |root|
        expect {
          described_class.load(write_lock(root, <<~LOCK))
            RUBY SKILLS
              remote: https://rubyskills.org

              rails/conventions (1.0.0)
                sha256: #{sha("a")}

              rails/conventions (1.1.0)
                sha256: #{sha("b")}

            DEPENDENCIES
              rails/conventions (~> 1.0)
          LOCK
        }.to raise_error(RubySkills::Lockfile::Error, /Duplicated locked skill/)
      end
    end

    it "rejects a malformed dependency" do
      with_tmp_project do |root|
        expect {
          described_class.load(write_lock(root, <<~LOCK))
            RUBY SKILLS
              remote: https://rubyskills.org

            DEPENDENCIES
              rails-conventions (~> 1.0)
          LOCK
        }.to raise_error(RubySkills::Lockfile::Error, /Malformed dependency/)
      end
    end

    it "rejects a malformed dependency requirement" do
      with_tmp_project do |root|
        expect {
          described_class.load(write_lock(root, <<~LOCK))
            RUBY SKILLS
              remote: https://rubyskills.org

            DEPENDENCIES
              rails/conventions (not a requirement)
          LOCK
        }.to raise_error(RubySkills::Lockfile::Error, /Malformed dependency/)
      end
    end

    it "rejects a malformed section" do
      with_tmp_project do |root|
        expect {
          described_class.load(write_lock(root, <<~LOCK))
            PLATFORMS
              ruby
          LOCK
        }.to raise_error(RubySkills::Lockfile::Error, /Malformed section/)
      end
    end

    it "rejects an invalid source" do
      with_tmp_project do |root|
        expect {
          described_class.load(write_lock(root, <<~LOCK))
            RUBY SKILLS
              remote: not-a-url

            DEPENDENCIES
          LOCK
        }.to raise_error(RubySkills::Lockfile::Error, /Invalid source/)
      end
    end
  end

  describe "#satisfies?" do
    it "is true when the locked version matches the requirement" do
      lockfile = build_lock(
        skills: [conventions],
        dependencies: [dep("rails/conventions", "~> 1.0")]
      )

      expect(lockfile.satisfies?(dep("rails/conventions", "~> 1.0"))).to be true
    end

    it "is false when the skill is missing or the version is too old" do
      lockfile = build_lock(
        skills: [conventions],
        dependencies: [dep("rails/conventions", "~> 1.0")]
      )

      expect(lockfile.satisfies?(dep("rails/missing", "~> 1.0"))).to be false
      expect(lockfile.satisfies?(dep("rails/conventions", "~> 2.0"))).to be false
    end
  end

  describe "#stale_against?" do
    let(:lockfile) do
      build_lock(
        skills: [conventions],
        dependencies: [dep("rails/conventions", "~> 1.0")]
      )
    end

    it "is false when the Skillfile matches the lock" do
      skillfile = skillfile_with(dep("rails/conventions", "~> 1.0"))

      expect(lockfile.stale_against?(skillfile)).to be false
    end

    it "is true when a Skillfile dependency is missing from the lock" do
      extra = skillfile_with(
        dep("rails/conventions", "~> 1.0"),
        dep("rails/request-specs", "~> 2.1")
      )
      empty_lock = build_lock(skills: [], dependencies: [])
      missing = skillfile_with(dep("rails/conventions", "~> 1.0"))

      expect(lockfile.stale_against?(extra)).to be true
      expect(empty_lock.stale_against?(missing)).to be true
    end

    it "is true when the locked version no longer satisfies the Skillfile" do
      expect(lockfile.stale_against?(skillfile_with(dep("rails/conventions", "~> 2.0")))).to be true
    end

    it "is true when a dependency was removed from the Skillfile" do
      expect(lockfile.stale_against?(skillfile_with)).to be true
    end
  end
end
