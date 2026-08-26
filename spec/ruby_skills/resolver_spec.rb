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
        RubySkills::Resolver::NoCompatibleVersion,
        %r{rails/conventions that satisfies ~> 2.0}
      )
    end
  end

  describe "single dependency" do
    it "resolves one Skillfile skill with no transitives" do
      client = catalog { |registry| registry.add("rails/conventions", "1.3.2") }

      resolution = resolve(
        skillfile_with(dep("rails/conventions", "~> 1.0")),
        client: client
      )

      expect(resolution.skills.map(&:name)).to eq(["rails/conventions"])
      expect(resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.3.2"))
      expect(resolution.find("rails/conventions").dependencies).to eq([])
    end
  end

  describe "multiple dependencies" do
    it "resolves several independent Skillfile skills" do
      client = catalog { |registry|
        registry.add("rails/conventions", "1.3.2")
        registry.add("rails/request-specs", "2.1.4")
      }

      resolution = resolve(
        skillfile_with(
          dep("rails/conventions", "~> 1.0"),
          dep("rails/request-specs", "~> 2.1")
        ),
        client: client
      )

      expect(resolution.skills.map(&:name)).to eq(
        ["rails/conventions", "rails/request-specs"]
      )
      expect(resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.3.2"))
      expect(resolution.find("rails/request-specs").version).to eq(Gem::Version.new("2.1.4"))
    end
  end

  describe "shared dependency" do
    def shared_registry
      catalog { |registry|
        registry.add(
          "rails/request-specs", "2.1.0",
          dependencies: [["rails/conventions", ">= 1.5"]]
        )
        registry.add(
          "rails/security", "1.3.0",
          dependencies: [["rails/conventions", "~> 1.0"]]
        )
        registry.add("rails/conventions", "1.4.0")
        registry.add("rails/conventions", "1.5.0")
        registry.add("rails/conventions", "1.8.0")
        registry.add("rails/conventions", "2.0.0")
      }
    end

    it "picks the highest version that satisfies every parent requirement" do
      resolution = resolve(
        skillfile_with(
          dep("rails/request-specs", "~> 2.0"),
          dep("rails/security", "~> 1.0")
        ),
        client: shared_registry
      )

      expect(resolution.find("rails/request-specs").version).to eq(Gem::Version.new("2.1.0"))
      expect(resolution.find("rails/security").version).to eq(Gem::Version.new("1.3.0"))
      expect(resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.8.0"))
    end

    it "records provenance for the shared skill" do
      conventions = resolve(
        skillfile_with(
          dep("rails/request-specs", "~> 2.0"),
          dep("rails/security", "~> 1.0")
        ),
        client: shared_registry
      ).find("rails/conventions")

      expect(conventions.required_by.map { |term|
        [term.parent_name, term.requirement.to_s]
      }).to eq(
        [["rails/request-specs", ">= 1.5"], ["rails/security", "~> 1.0"]]
      )
    end

    it "writes nested transitives under parents and only directs under DEPENDENCIES" do
      lockfile = resolve(
        skillfile_with(
          dep("rails/request-specs", "~> 2.0"),
          dep("rails/security", "~> 1.0")
        ),
        client: shared_registry
      ).to_lockfile

      expect(lockfile.serialize).to eq(<<~LOCK)
        RUBY SKILLS
          remote: https://rubyskills.org

          rails/conventions (1.8.0)
            sha256: #{sha("rails/conventions", "1.8.0")}

          rails/request-specs (2.1.0)
            rails/conventions (>= 1.5)
            sha256: #{sha("rails/request-specs", "2.1.0")}

          rails/security (1.3.0)
            rails/conventions (~> 1.0)
            sha256: #{sha("rails/security", "1.3.0")}

        DEPENDENCIES
          rails/request-specs (~> 2.0)
          rails/security (~> 1.0)
      LOCK
    end
  end

  describe "deep dependency tree" do
    it "walks several layers of transitives" do
      client = catalog { |registry|
        registry.add("demo/a", "1.0.0", dependencies: [["demo/b", "~> 1.0"]])
        registry.add("demo/b", "1.2.0", dependencies: [["demo/c", ">= 2.0"]])
        registry.add("demo/c", "2.1.0", dependencies: [["demo/d", "~> 3.1.0"]])
        registry.add("demo/d", "3.1.4")
        registry.add("demo/d", "3.2.0")
      }

      resolution = resolve(skillfile_with(dep("demo/a", "~> 1.0")), client: client)

      expect(resolution.skills.map { |skill| [skill.name, skill.version.to_s] }).to eq(
        [["demo/a", "1.0.0"], ["demo/b", "1.2.0"], ["demo/c", "2.1.0"], ["demo/d", "3.1.4"]]
      )
      expect(resolution.find("demo/d").required_by.map(&:parent_name)).to eq(["demo/c"])
    end
  end

  describe "cycle detection" do
    it "fails when two skills depend on each other" do
      client = catalog { |registry|
        registry.add("demo/a", "1.0.0", dependencies: [["demo/b", "~> 1.0"]])
        registry.add("demo/b", "1.0.0", dependencies: [["demo/a", "~> 1.0"]])
      }

      expect {
        resolve(skillfile_with(dep("demo/a", "~> 1.0")), client: client)
      }.to raise_error(
        RubySkills::Resolver::CircularDependency,
        "Circular dependency: demo/a -> demo/b -> demo/a"
      )
    end

    it "fails on a longer cycle" do
      client = catalog { |registry|
        registry.add("demo/a", "1.0.0", dependencies: [["demo/b", ">= 0"]])
        registry.add("demo/b", "1.0.0", dependencies: [["demo/c", ">= 0"]])
        registry.add("demo/c", "1.0.0", dependencies: [["demo/a", ">= 0"]])
      }

      expect {
        resolve(skillfile_with(dep("demo/a", "~> 1.0")), client: client)
      }.to raise_error(RubySkills::Resolver::CircularDependency, %r{demo/a -> demo/b -> demo/c})
    end
  end

  describe "version conflict" do
    it "fails when no published version satisfies every requirement" do
      client = catalog { |registry|
        registry.add("ruby/a", "1.0.0", dependencies: [["ruby/foo", "~> 1.0"]])
        registry.add("ruby/b", "1.0.0", dependencies: [["ruby/foo", ">= 2.0"]])
        registry.add("ruby/foo", "1.5.0")
        registry.add("ruby/foo", "2.0.0")
      }

      expect {
        resolve(
          skillfile_with(dep("ruby/a", "~> 1.0"), dep("ruby/b", "~> 1.0")),
          client: client
        )
      }.to raise_error(RubySkills::Resolver::VersionConflict, <<~MSG.chomp)
        Unable to resolve ruby/foo.

        Requirements:
        ruby/a -> ruby/foo (~> 1.0)
        ruby/b -> ruby/foo (>= 2.0)

        No published version satisfies all requirements.
      MSG
    end
  end

  describe "lock preservation with transitives" do
    def shared_graph_lockfile
      RubySkills::Lockfile.new(
        source: "https://rubyskills.org",
        skills: [
          locked("rails/conventions", "1.5.0"),
          locked("rails/request-specs", "2.1.0"),
          locked("rails/security", "1.3.0")
        ],
        dependencies: [
          dep("rails/request-specs", "~> 2.0"),
          dep("rails/security", "~> 1.0")
        ]
      )
    end

    it "keeps a locked shared dependency that still satisfies every requirement" do
      client = catalog { |registry|
        registry.add(
          "rails/request-specs", "2.1.0",
          dependencies: [["rails/conventions", ">= 1.5"]]
        )
        registry.add(
          "rails/security", "1.3.0",
          dependencies: [["rails/conventions", "~> 1.0"]]
        )
        registry.add("rails/conventions", "1.5.0")
        registry.add("rails/conventions", "1.8.0")
      }
      skillfile = skillfile_with(
        dep("rails/request-specs", "~> 2.0"),
        dep("rails/security", "~> 1.0")
      )
      lockfile = shared_graph_lockfile

      installed = resolve(skillfile, client: client, lockfile: lockfile)
      updated = resolve(skillfile, client: client, lockfile: lockfile, update: true)

      expect(installed.find("rails/conventions").version).to eq(Gem::Version.new("1.5.0"))
      expect(updated.find("rails/conventions").version).to eq(Gem::Version.new("1.8.0"))
    end
  end

  describe "targeted update" do
    it "re-resolves only the named skill and keeps other valid pins" do
      client = catalog { |registry|
        registry.add(
          "rails/request-specs", "2.1.0",
          dependencies: [["rails/conventions", ">= 1.5"]]
        )
        registry.add(
          "rails/request-specs", "2.2.0",
          dependencies: [["rails/conventions", ">= 1.5"]]
        )
        registry.add(
          "rails/security", "1.3.0",
          dependencies: [["rails/conventions", "~> 1.0"]]
        )
        registry.add("rails/conventions", "1.5.0")
        registry.add("rails/conventions", "1.8.0")
      }
      lockfile = RubySkills::Lockfile.new(
        source: "https://rubyskills.org",
        skills: [
          locked("rails/conventions", "1.5.0"),
          locked("rails/request-specs", "2.1.0"),
          locked("rails/security", "1.3.0")
        ],
        dependencies: [
          dep("rails/request-specs", "~> 2.0"),
          dep("rails/security", "~> 1.0")
        ]
      )

      resolution = resolve(
        skillfile_with(
          dep("rails/request-specs", "~> 2.0"),
          dep("rails/security", "~> 1.0")
        ),
        client: client,
        lockfile: lockfile,
        update: "rails/request-specs"
      )

      expect(resolution.find("rails/request-specs").version).to eq(Gem::Version.new("2.2.0"))
      expect(resolution.find("rails/security").version).to eq(Gem::Version.new("1.3.0"))
      expect(resolution.find("rails/conventions").version).to eq(Gem::Version.new("1.5.0"))
    end
  end

  describe "yanked transitive versions" do
    it "skips a yanked shared dependency and uses the next compatible release" do
      client = catalog { |registry|
        registry.add("demo/app", "1.0.0", dependencies: [["demo/lib", "~> 1.0"]])
        registry.add("demo/lib", "1.2.0")
        registry.add("demo/lib", "1.3.0", yanked: true)
      }

      resolution = resolve(skillfile_with(dep("demo/app", "~> 1.0")), client: client)

      expect(resolution.find("demo/lib").version).to eq(Gem::Version.new("1.2.0"))
    end
  end

  describe "deterministic resolution" do
    it "returns the same graph for the same catalog regardless of insertion order" do
      first = catalog { |registry|
        registry.add("rails/security", "1.3.0", dependencies: [["rails/conventions", "~> 1.0"]])
        registry.add(
          "rails/request-specs", "2.1.0",
          dependencies: [["rails/conventions", ">= 1.5"]]
        )
        registry.add("rails/conventions", "2.0.0")
        registry.add("rails/conventions", "1.8.0")
        registry.add("rails/conventions", "1.5.0")
        registry.add("rails/conventions", "1.4.0")
      }
      second = catalog { |registry|
        registry.add("rails/conventions", "1.4.0")
        registry.add("rails/conventions", "1.5.0")
        registry.add("rails/conventions", "1.8.0")
        registry.add("rails/conventions", "2.0.0")
        registry.add(
          "rails/request-specs", "2.1.0",
          dependencies: [["rails/conventions", ">= 1.5"]]
        )
        registry.add("rails/security", "1.3.0", dependencies: [["rails/conventions", "~> 1.0"]])
      }
      skillfile = skillfile_with(
        dep("rails/security", "~> 1.0"),
        dep("rails/request-specs", "~> 2.0")
      )

      left = resolve(skillfile, client: first)
      right = resolve(skillfile, client: second)

      expect(left.to_lockfile.serialize).to eq(right.to_lockfile.serialize)
      expect(left.skills.map(&:name)).to eq(left.skills.map(&:name).sort)
    end
  end

  describe "registry caching" do
    it "fetches each skill and version at most once per session" do
      inner = catalog { |registry|
        registry.add(
          "rails/request-specs", "2.1.0",
          dependencies: [["rails/conventions", ">= 1.5"]]
        )
        registry.add(
          "rails/security", "1.3.0",
          dependencies: [["rails/conventions", "~> 1.0"]]
        )
        registry.add("rails/conventions", "1.8.0")
        registry.add("rails/conventions", "2.0.0")
      }
      client = RubySkillsSpec::CountingCatalogClient.new(inner)

      resolve(
        skillfile_with(
          dep("rails/request-specs", "~> 2.0"),
          dep("rails/security", "~> 1.0")
        ),
        client: client
      )

      expect(client.skill_calls.values).to all(eq(1))
      expect(client.version_calls.values).to all(eq(1))
    end
  end

  describe "backtracking" do
    it "tries a lower parent version when the highest parent cannot satisfy the graph" do
      client = catalog { |registry|
        registry.add("pkg/a", "2.0.0", dependencies: [["pkg/foo", "~> 2.0"]])
        registry.add("pkg/a", "1.0.0", dependencies: [["pkg/foo", "~> 1.0"]])
        registry.add("pkg/b", "1.0.0", dependencies: [["pkg/foo", "~> 1.0"]])
        registry.add("pkg/foo", "1.4.0")
        registry.add("pkg/foo", "2.1.0")
      }

      resolution = resolve(
        skillfile_with(dep("pkg/a", ">= 1.0"), dep("pkg/b", "~> 1.0")),
        client: client
      )

      expect(resolution.find("pkg/a").version).to eq(Gem::Version.new("1.0.0"))
      expect(resolution.find("pkg/foo").version).to eq(Gem::Version.new("1.4.0"))
    end
  end
end
