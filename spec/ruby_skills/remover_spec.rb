# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::Remover do
  def config_for(root)
    RubySkills::Config.new(root: root)
  end

  def plant_installed(root, name, version)
    path = RubySkills::Install.destination(name, version, config: config_for(root))
    FileUtils.mkdir_p(path)
    path.join("SKILL.md").write("# #{name}\n")
    path
  end

  def write_lock(root, name:, version:)
    RubySkills::Lockfile.new(
      source: "https://rubyskills.org",
      skills: [
        RubySkills::LockedSkill.new(
          name: name,
          version: version,
          checksum: "sha256:#{Digest::SHA256.hexdigest("#{name}@#{version}")}"
        )
      ],
      dependencies: [
        RubySkills::Dependency.new(name: name, requirement: Gem::Requirement.new(">= 0"))
      ]
    ).write(root.join("Skills.lock"))
  end

  def remove(name, root:, output: StringIO.new)
    described_class.new(config: config_for(root), output: output).remove(name)
    output.string
  end

  it "prints a success message when the skill is not installed" do
    with_tmp_project do |root|
      output = remove("rails/request-specs", root: root)

      expect(output).to eq("rails/request-specs is not installed.\n")
    end
  end

  it "deletes the installed version without changing Skillfile or Skills.lock" do
    with_tmp_project do |root|
      skillfile = root.join("Skillfile")
      skillfile.write(<<~RUBY)
        source "https://rubyskills.org"

        skill "rails/request-specs", "~> 2.1"
      RUBY
      write_lock(root, name: "rails/request-specs", version: "2.1.4")
      planted = plant_installed(root, "rails/request-specs", "2.1.4")
      original_skillfile = skillfile.read
      original_lock = root.join("Skills.lock").read

      output = remove("rails/request-specs", root: root)

      expect(output).to include("Removing rails/request-specs 2.1.4...")
      expect(output).to include("✓ removed")
      expect(planted).not_to exist
      expect(skillfile.read).to eq(original_skillfile)
      expect(root.join("Skills.lock").read).to eq(original_lock)
    end
  end

  it "warns when the skill remains in Skills.lock" do
    with_tmp_project do |root|
      root.join("Skillfile").write(<<~RUBY)
        source "https://rubyskills.org"

        skill "rails/request-specs", "~> 2.1"
      RUBY
      write_lock(root, name: "rails/request-specs", version: "2.1.4")
      plant_installed(root, "rails/request-specs", "2.1.4")

      output = remove("rails/request-specs", root: root)

      expect(output).to include(
        "rails/request-specs is still referenced by this project's Skills.lock."
      )
      expect(output).to include("Run with --save to remove it from the project configuration.")
    end
  end

  it "invokes adapter sync after a successful removal" do
    with_tmp_project do |root|
      plant_installed(root, "rails/request-specs", "2.1.4")
      allow(RubySkills::Adapters).to receive(:sync_remove)

      remove("rails/request-specs", root: root)

      expect(RubySkills::Adapters).to have_received(:sync_remove).with(
        "rails/request-specs",
        root: root
      )
    end
  end
end
