# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::ProjectRemove do
  def checksum(name, version)
    "sha256:#{Digest::SHA256.hexdigest("#{name}@#{version}")}"
  end

  def config_for(root)
    RubySkills::Config.new(root: root)
  end

  def plant_installed(root, name, version)
    path = RubySkills::Install.destination(name, version, config: config_for(root))
    FileUtils.mkdir_p(path)
    path.join("SKILL.md").write("# #{name}\n")
    path
  end

  def write_skillfile(root, contents)
    root.join("Skillfile").write(contents)
  end

  def write_lock(root, entries)
    RubySkills::Lockfile.new(
      source: "https://rubyskills.org",
      skills: entries.map { |name, version, _requirement|
        RubySkills::LockedSkill.new(name: name, version: version, checksum: checksum(name, version))
      },
      dependencies: entries.map { |name, _version, requirement|
        RubySkills::Dependency.new(
          name: name,
          requirement: Gem::Requirement.new(requirement)
        )
      }
    ).write(root.join("Skills.lock"))
  end

  def catalog(*releases)
    client = RubySkillsSpec::CatalogClient.new
    releases.each do |name, version|
      client.add(name, version)
    end
    client
  end

  def remove(root, name, client: nil, output: StringIO.new)
    described_class.new(
      name: name,
      client: client || RubySkillsSpec::CatalogClient.new,
      starting_directory: root,
      output: output
    ).run
    output.string
  end

  def two_skill_project(root)
    write_skillfile(
      root,
      <<~RUBY
        source "https://rubyskills.org"

        skill "demo/a", "~> 1.0"
        skill "demo/b", "~> 2.0"
      RUBY
    )
    write_lock(root, [["demo/a", "1.0.0", "~> 1.0"], ["demo/b", "2.0.0", "~> 2.0"]])
    plant_installed(root, "demo/a", "1.0.0")
    plant_installed(root, "demo/b", "2.0.0")
  end

  it "removes the declaration, lock entry, and installed artifact" do # rubocop:disable RSpec/MultipleExpectations
    with_tmp_project do |root|
      two_skill_project(root)

      output = remove(root, "demo/a", client: catalog(["demo/b", "2.0.0"]))

      expect(output).to include("Removing demo/a from project...")
      expect(output).to include("✓ Skillfile updated")
      expect(output).to include("✓ demo/a 1.0.0 removed")
      expect(output).to include("✓ Skills.lock updated")
      expect(output).to include("Removed demo/a.")
      expect(root.join("Skillfile").read).to eq(<<~RUBY)
        source "https://rubyskills.org"

        skill "demo/b", "~> 2.0"
      RUBY
      lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))
      expect(lockfile.locked?("demo/a")).to be false
      expect(lockfile.find("demo/b").version).to eq(Gem::Version.new("2.0.0"))
      expect(lockfile.dependencies.map(&:name)).to eq(["demo/b"])
      expect(
        RubySkills::Install.installed?("demo/a", "1.0.0", config: config_for(root))
      ).to be false
      expect(
        RubySkills::Install.installed?("demo/b", "2.0.0", config: config_for(root))
      ).to be true
    end
  end

  it "preserves remaining requirement strings and lock pins" do
    with_tmp_project do |root|
      two_skill_project(root)
      remove(root, "demo/a", client: catalog(["demo/b", "2.0.0"], ["demo/b", "2.9.0"]))

      expect(root.join("Skillfile").read).to include('skill "demo/b", "~> 2.0"')
      lockfile = RubySkills::Lockfile.load(root.join("Skills.lock"))
      expect(lockfile.find("demo/b").version).to eq(Gem::Version.new("2.0.0"))
      expect(lockfile.serialize).to include("demo/b (2.0.0)")
      expect(lockfile.serialize).not_to include("demo/a")
      expect(lockfile.serialize).to eq(
        RubySkills::Lockfile.load(root.join("Skills.lock")).serialize
      )
    end
  end

  it "updates Skillfile and lock when the artifact is missing" do
    with_tmp_project do |root|
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"

        skill "demo/a", "~> 1.0"
      RUBY
      write_lock(root, [["demo/a", "1.0.0", "~> 1.0"]])

      output = remove(root, "demo/a")

      expect(output).to include("✓ Skillfile updated")
      expect(output).to include("✓ Skills.lock updated")
      expect(output).to include("- no installed artifact to remove")
      expect(root.join("Skillfile").read).not_to include("demo/a")
      expect(RubySkills::Lockfile.load(root.join("Skills.lock")).skills).to eq([])
    end
  end

  it "raises when the skill is not declared" do
    with_tmp_project do |root|
      write_skillfile(root, 'skill "demo/b"')
      original = root.join("Skillfile").read

      expect {
        remove(root, "demo/a")
      }.to raise_error(
        RubySkills::ProjectRemove::NotDeclared,
        "demo/a is not declared in Skillfile."
      )
      expect(root.join("Skillfile").read).to eq(original)
    end
  end

  it "raises when Skillfile is missing" do
    with_tmp_project do |root|
      expect {
        remove(root, "demo/a")
      }.to raise_error(RubySkills::Skillfile::Error, a_string_including("Skillfile not found"))
    end
  end

  it "does not mutate the project when Skillfile is invalid" do
    with_tmp_project do |root|
      write_skillfile(root, "skill (")
      plant_installed(root, "demo/a", "1.0.0")

      expect {
        remove(root, "demo/a")
      }.to raise_error(RubySkills::Skillfile::Error, a_string_including("Malformed Skillfile"))
      expect(RubySkills::Install.installed?("demo/a", "1.0.0", config: config_for(root))).to be true
    end
  end

  it "does not mutate the project when Skills.lock is invalid" do
    with_tmp_project do |root|
      write_skillfile(root, <<~RUBY)
        source "https://rubyskills.org"

        skill "demo/a"
        skill "demo/b"
      RUBY
      root.join("Skills.lock").write("not a lockfile\n")
      original = root.join("Skillfile").read

      expect {
        remove(root, "demo/a")
      }.to raise_error(RubySkills::Lockfile::Error)
      expect(root.join("Skillfile").read).to eq(original)
    end
  end

  it "does not mutate the project when resolution fails" do
    with_tmp_project do |root|
      two_skill_project(root)
      original_skillfile = root.join("Skillfile").read
      original_lock = root.join("Skills.lock").read

      expect {
        remove(root, "demo/a", client: catalog(["demo/missing", "1.0.0"]))
      }.to raise_error(RubySkills::Resolver::Error)

      expect(root.join("Skillfile").read).to eq(original_skillfile)
      expect(root.join("Skills.lock").read).to eq(original_lock)
      expect(RubySkills::Install.installed?("demo/a", "1.0.0", config: config_for(root))).to be true
    end
  end

  it "reports a filesystem failure after Skillfile and lock were written" do
    with_tmp_project do |root|
      two_skill_project(root)
      allow(RubySkills::Install).to receive(:assert_removable!)
      allow(RubySkills::Install).to receive(:remove_version!).and_raise(
        Errno::EACCES, "denied"
      )

      expect {
        remove(root, "demo/a", client: catalog(["demo/b", "2.0.0"]))
      }.to raise_error(
        RubySkills::Error,
        a_string_including("Skillfile and Skills.lock were updated").and(
          a_string_including("Failed to remove demo/a 1.0.0")
        )
      )
      expect(root.join("Skillfile").read).not_to include("demo/a")
      expect(RubySkills::Lockfile.load(root.join("Skills.lock")).locked?("demo/a")).to be false
    end
  end

  it "invokes adapter sync after a successful project removal" do
    with_tmp_project do |root|
      two_skill_project(root)
      allow(RubySkills::Adapters).to receive(:sync_remove)

      remove(root, "demo/a", client: catalog(["demo/b", "2.0.0"]))

      expect(RubySkills::Adapters).to have_received(:sync_remove).with("demo/a", root: root)
    end
  end

  it "reports adapter sync failure separately from a successful removal" do
    with_tmp_project do |root|
      two_skill_project(root)
      allow(RubySkills::Adapters).to receive(:sync_remove).and_raise(StandardError, "link failed")

      output = remove(root, "demo/a", client: catalog(["demo/b", "2.0.0"]))

      expect(output).to include("Removed demo/a.")
      expect(output).to include("Warning: adapter sync failed: link failed")
      expect(root.join("Skillfile").read).not_to include("demo/a")
    end
  end
end
