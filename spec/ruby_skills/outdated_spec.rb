# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::Outdated do
  def sha(name, version)
    Digest::SHA256.hexdigest("#{name}@#{version}")
  end

  def checksum(name, version)
    "sha256:#{sha(name, version)}"
  end

  def dep(name, requirement)
    RubySkills::Dependency.new(name: name, requirement: Gem::Requirement.new(requirement))
  end

  def locked(name, version)
    RubySkills::LockedSkill.new(name: name, version: version, checksum: checksum(name, version))
  end

  def write_project(root, dependencies:, locked_skills: nil)
    root.join("Skillfile").write(<<~RUBY)
      source "https://rubyskills.org"

      #{dependencies.map { |name, requirement|
        %(skill "#{name}", "#{requirement}")
      }.join("\n")}
    RUBY
    return if locked_skills.nil?

    skills = locked_skills.map { |name, version| locked(name, version) }
    RubySkills::Lockfile.new(
      source: "https://rubyskills.org",
      skills: skills,
      dependencies: dependencies.map { |name, requirement| dep(name, requirement) }
    ).write(root.join("Skills.lock"))
  end

  def catalog
    client = RubySkillsSpec::CatalogClient.new
    yield client
    client
  end

  def outdated(root, client:, name: nil)
    described_class.new(name: name, client: client, starting_directory: root).run
  end

  def row(result, name)
    result.rows.find { |entry| entry.name == name }
  end

  def three_skill_project(root)
    write_project(
      root,
      dependencies: {
        "rails/conventions" => "~> 1.0",
        "rails/request-specs" => "~> 2.1.0",
        "ruby/gem-development" => "~> 0.4.0"
      },
      locked_skills: {
        "rails/conventions" => "1.2.0",
        "rails/request-specs" => "2.1.4",
        "ruby/gem-development" => "0.4.1"
      }
    )
  end

  def three_skill_catalog
    catalog { |registry|
      registry.add("rails/conventions", "1.2.0")
      registry.add("rails/conventions", "1.4.3")
      registry.add("rails/conventions", "2.0.0")
      registry.add("rails/request-specs", "2.1.4")
      registry.add("rails/request-specs", "2.2.0")
      registry.add("ruby/gem-development", "0.4.1")
    }
  end

  it "reports update available, constrained, and current" do
    with_tmp_project do |root|
      three_skill_project(root)
      result = outdated(root, client: three_skill_catalog)

      expect(row(result, "rails/conventions")).to have_attributes(
        current: Gem::Version.new("1.2.0"),
        allowed: Gem::Version.new("1.4.3"),
        latest: Gem::Version.new("2.0.0"),
        status: :update_available
      )
      expect(row(result, "rails/request-specs")).to have_attributes(
        current: Gem::Version.new("2.1.4"),
        allowed: Gem::Version.new("2.1.4"),
        latest: Gem::Version.new("2.2.0"),
        status: :constrained
      )
      expect(row(result, "ruby/gem-development")).to have_attributes(
        current: Gem::Version.new("0.4.1"),
        allowed: Gem::Version.new("0.4.1"),
        latest: Gem::Version.new("0.4.1"),
        status: :current
      )
      expect(result.exit_status).to eq(1)
    end
  end

  it "reports missing when the skill is not locked" do
    with_tmp_project do |root|
      write_project(root, dependencies: { "rails/conventions" => "~> 1.0" }, locked_skills: {})
      client = catalog { |registry|
        registry.add("rails/conventions", "1.4.3")
      }

      result = outdated(root, client: client)
      conventions = row(result, "rails/conventions")

      expect(conventions.current).to be_nil
      expect(conventions.allowed).to eq(Gem::Version.new("1.4.3"))
      expect(conventions.status).to eq(:missing)
      expect(result.exit_status).to eq(1)
    end
  end

  it "reports missing when the skill is not in the registry" do
    with_tmp_project do |root|
      write_project(
        root,
        dependencies: { "rails/missing" => "~> 1.0" },
        locked_skills: { "rails/missing" => "1.0.0" }
      )

      result = outdated(root, client: RubySkillsSpec::CatalogClient.new)
      missing = row(result, "rails/missing")

      expect(missing.current).to eq(Gem::Version.new("1.0.0"))
      expect(missing.allowed).to be_nil
      expect(missing.latest).to be_nil
      expect(missing.status).to eq(:missing)
    end
  end

  it "reports when the locked version is yanked or unpublished" do
    with_tmp_project do |root|
      write_project(
        root,
        dependencies: { "rails/conventions" => "~> 1.0" },
        locked_skills: { "rails/conventions" => "1.2.0" }
      )
      client = catalog { |registry|
        registry.add("rails/conventions", "1.2.0", yanked: true)
        registry.add("rails/conventions", "1.4.3")
        registry.add("rails/conventions", "2.0.0")
      }

      result = outdated(root, client: client)
      conventions = row(result, "rails/conventions")

      expect(conventions.current).to eq(Gem::Version.new("1.2.0"))
      expect(conventions.allowed).to eq(Gem::Version.new("1.4.3"))
      expect(conventions.latest).to eq(Gem::Version.new("2.0.0"))
      expect(conventions.status).to eq(:locked_version_unavailable)
    end
  end

  it "uses Gem::Version, not lexicographic order" do
    with_tmp_project do |root|
      write_project(
        root,
        dependencies: { "rails/conventions" => "~> 1.0" },
        locked_skills: { "rails/conventions" => "1.9.0" }
      )
      client = catalog { |registry|
        registry.add("rails/conventions", "1.9.0")
        registry.add("rails/conventions", "1.10.0")
      }

      result = outdated(root, client: client)
      conventions = row(result, "rails/conventions")

      expect(conventions.allowed).to eq(Gem::Version.new("1.10.0"))
      expect(conventions.latest).to eq(Gem::Version.new("1.10.0"))
      expect(conventions.status).to eq(:update_available)
    end
  end

  it "limits the report to one Skillfile dependency" do
    with_tmp_project do |root|
      write_project(
        root,
        dependencies: {
          "rails/conventions" => "~> 1.0",
          "rails/request-specs" => "~> 2.1.0"
        },
        locked_skills: {
          "rails/conventions" => "1.2.0",
          "rails/request-specs" => "2.1.4"
        }
      )
      client = catalog { |registry|
        registry.add("rails/conventions", "1.2.0")
        registry.add("rails/conventions", "1.4.3")
        registry.add("rails/request-specs", "2.1.4")
        registry.add("rails/request-specs", "2.2.0")
      }

      result = outdated(root, client: client, name: "rails/conventions")

      expect(result.rows.map(&:name)).to eq(["rails/conventions"])
      expect(row(result, "rails/conventions").status).to eq(:update_available)
    end
  end

  it "raises when the named skill is not in the Skillfile" do
    with_tmp_project do |root|
      write_project(root, dependencies: { "rails/conventions" => "~> 1.0" }, locked_skills: {})

      expect {
        outdated(root, client: RubySkillsSpec::CatalogClient.new, name: "rails/security")
      }.to raise_error(RubySkills::Error, "Skill `rails/security` is not in the Skillfile")
    end
  end

  it "does not write Skillfile, Skills.lock, or installed artifacts" do
    with_tmp_project do |root|
      write_project(
        root,
        dependencies: { "rails/conventions" => "~> 1.0" },
        locked_skills: { "rails/conventions" => "1.2.0" }
      )
      planted = root.join(".ruby-skills", "rails", "conventions", "1.2.0")
      FileUtils.mkdir_p(planted)
      planted.join("SKILL.md").write("keep me\n")
      before = {
        skillfile: root.join("Skillfile").read,
        lock: root.join("Skills.lock").read,
        artifact: planted.join("SKILL.md").read
      }
      client = catalog { |registry|
        registry.add("rails/conventions", "1.2.0")
        registry.add("rails/conventions", "1.4.3")
      }

      outdated(root, client: client)

      expect(root.join("Skillfile").read).to eq(before[:skillfile])
      expect(root.join("Skills.lock").read).to eq(before[:lock])
      expect(planted.join("SKILL.md").read).to eq(before[:artifact])
    end
  end

  it "fetches each skill once" do
    with_tmp_project do |root|
      write_project(
        root,
        dependencies: { "rails/conventions" => "~> 1.0" },
        locked_skills: { "rails/conventions" => "1.2.0" }
      )
      inner = catalog { |registry|
        registry.add("rails/conventions", "1.2.0")
        registry.add("rails/conventions", "1.4.3")
      }
      client = RubySkillsSpec::CountingCatalogClient.new(inner)

      outdated(root, client: client)

      expect(client.skill_calls).to eq("rails/conventions" => 1)
      expect(client.version_calls).to eq({})
    end
  end

  it "exits 0 when every skill is current" do
    with_tmp_project do |root|
      write_project(
        root,
        dependencies: { "ruby/gem-development" => "~> 0.4.0" },
        locked_skills: { "ruby/gem-development" => "0.4.1" }
      )
      client = catalog { |registry| registry.add("ruby/gem-development", "0.4.1") }

      result = outdated(root, client: client)

      expect(result.exit_status).to eq(0)
      expect(result.as_json).to eq(
        [
          {
            "name" => "ruby/gem-development",
            "current" => "0.4.1",
            "allowed" => "0.4.1",
            "latest" => "0.4.1",
            "status" => "current"
          }
        ]
      )
    end
  end

  describe RubySkills::Outdated::Report do
    it "renders a human-readable table" do
      result = RubySkills::Outdated::Result.new(
        rows: [
          RubySkills::Outdated::Row.new(
            name: "rails/conventions",
            current: Gem::Version.new("1.2.0"),
            allowed: Gem::Version.new("1.4.3"),
            latest: Gem::Version.new("2.0.0"),
            status: :update_available
          )
        ]
      )

      expect(described_class.new(result).to_s).to eq(<<~TABLE)
        Skill              Current  Allowed  Latest  Status
        rails/conventions  1.2.0    1.4.3    2.0.0   update available
      TABLE
    end
  end
end
