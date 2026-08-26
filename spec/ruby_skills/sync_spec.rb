# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::Sync do
  def checksum(name, version)
    "sha256:#{Digest::SHA256.hexdigest("#{name}@#{version}")}"
  end

  def plant_installed(root, name, version)
    path = RubySkills::Install.destination(
      name, version, config: RubySkills::Config.new(root: root)
    )
    FileUtils.mkdir_p(path)
    path.join("SKILL.md").write("# #{name}\n")
    path
  end

  def write_project(root, entries)
    root.join("Skillfile").write(<<~RUBY)
      source "https://rubyskills.org"

      #{entries.map { |name, _version, requirement|
        %(skill "#{name}", "#{requirement}")
      }.join("\n")}
    RUBY
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
    entries.each { |name, version, _requirement| plant_installed(root, name, version) }
  end

  def sync(root, **options)
    output = StringIO.new
    described_class.new(starting_directory: root, output: output, **options).run
    output.string
  end

  it "symlinks locked skills into detected agents and reports the result" do
    with_tmp_project do |root|
      write_project(
        root,
        [
          ["rails/conventions", "1.3.2", "~> 1.3"],
          ["rails/request-specs", "2.1.4", "~> 2.1"]
        ]
      )
      FileUtils.mkdir_p(root.join(".claude"))
      FileUtils.mkdir_p(root.join(".codex"))

      output = sync(root)

      expect(output).to include(
        "Synchronizing Ruby Skills...",
        "Claude",
        "  ✓ rails/conventions@1.3.2",
        "  ✓ rails/request-specs@2.1.4",
        "Codex",
        "Cursor",
        "  not detected",
        "VS Code",
        "Synced 2 skills to 2 agents."
      )
      expect(root.join(".claude", "skills", "rails-conventions@1.3.2")).to be_symlink
      expect(root.join(".codex", "skills", "rails-request-specs@2.1.4")).to be_symlink
      expect(root.join(".cursor")).not_to exist
    end
  end

  it "limits work to --agent and supports dry-run" do
    with_tmp_project do |root|
      write_project(root, [["rails/request-specs", "2.0.0", "~> 2.0"]])
      FileUtils.mkdir_p(root.join(".claude"))
      described_class.new(starting_directory: root, output: StringIO.new).run
      FileUtils.rm_rf(root.join(".ruby-skills", "rails", "request-specs", "2.0.0"))
      write_project(root, [["rails/request-specs", "2.1.4", "~> 2.1"]])

      output = sync(root, agent: "claude", dry_run: true)

      expect(output).to include(
        "Would add:",
        "  Claude: rails/request-specs@2.1.4",
        "Would remove:",
        "  Claude: rails/request-specs@2.0.0"
      )
      expect(root.join(".claude", "skills", "rails-request-specs@2.0.0")).to be_symlink
      expect(root.join(".claude", "skills", "rails-request-specs@2.1.4")).not_to exist
    end
  end

  it "raises when a locked skill is not installed" do
    with_tmp_project do |root|
      write_project(root, [["rails/conventions", "1.3.2", "~> 1.3"]])
      FileUtils.rm_rf(root.join(".ruby-skills"))
      FileUtils.mkdir_p(root.join(".claude"))

      expect {
        sync(root)
      }.to raise_error(RubySkills::Error, /locked but not installed/)
    end
  end

  it "raises when Skills.lock is missing" do
    with_tmp_project do |root|
      root.join("Skillfile").write(%(source "https://rubyskills.org"\n))
      FileUtils.mkdir_p(root.join(".claude"))

      expect {
        sync(root)
      }.to raise_error(RubySkills::Error, /Skills.lock not found/)
    end
  end

  it "raises for an unknown agent" do
    with_tmp_project do |root|
      write_project(root, [["rails/conventions", "1.3.2", "~> 1.3"]])

      expect {
        sync(root, agent: "intellij")
      }.to raise_error(RubySkills::Error, /Unknown agent "intellij"/)
    end
  end
end
