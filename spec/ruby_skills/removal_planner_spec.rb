# frozen_string_literal: true

require "digest"
require "set"

RSpec.describe RubySkills::RemovalPlanner do
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

  def resolved(name, version)
    RubySkills::ResolvedSkill.new(
      name: name,
      version: version,
      checksum: "sha256:#{Digest::SHA256.hexdigest("#{name}@#{version}")}",
      source: "https://rubyskills.org"
    )
  end

  def locked(name, version)
    RubySkills::LockedSkill.new(
      name: name,
      version: version,
      checksum: "sha256:#{Digest::SHA256.hexdigest("#{name}@#{version}")}"
    )
  end

  def lockfile_with(*skills)
    RubySkills::Lockfile.new(
      source: "https://rubyskills.org",
      skills: skills,
      dependencies: skills.map { |skill| dep(skill.name) }
    )
  end

  def plant(root, name, version)
    path = RubySkills::Install.destination(
      name,
      version,
      config: RubySkills::Config.new(root: root)
    )
    FileUtils.mkdir_p(path)
    path
  end

  def plan_for(root, removed:, remaining:, lock:, installed:)
    installed.each do |name, version|
      plant(root, name, version)
    end
    remaining_deps = remaining.map { |name, _version| dep(name) }
    remaining_resolved = remaining.map { |name, version| resolved(name, version) }
    described_class.new(
      removed_name: removed,
      skillfile: skillfile_with(*remaining_deps),
      lockfile: lockfile_with(*lock.map { |name, version| locked(name, version) }),
      resolution: RubySkills::Resolution.new(
        source: "https://rubyskills.org",
        skills: remaining_resolved,
        dependencies: remaining_deps
      ),
      config: RubySkills::Config.new(root: root)
    ).plan
  end

  it "marks the removed locked skill as obsolete and removable" do
    with_tmp_project do |root|
      plan = plan_for(
        root,
        removed: "demo/a",
        remaining: [["demo/b", "2.0.0"]],
        lock: [["demo/a", "1.0.0"], ["demo/b", "2.0.0"]],
        installed: [["demo/a", "1.0.0"], ["demo/b", "2.0.0"]]
      )

      expect(plan.required_names).to eq(Set.new(["demo/b"]))
      expect(plan.obsolete_locked.map(&:name)).to eq(["demo/a"])
      expect(plan.artifacts).to contain_exactly(
        have_attributes(name: "demo/a", version: "1.0.0")
      )
    end
  end

  it "does not treat a stray installed skill as removable" do
    with_tmp_project do |root|
      plan = plan_for(
        root,
        removed: "demo/a",
        remaining: [["demo/b", "2.0.0"]],
        lock: [["demo/a", "1.0.0"], ["demo/b", "2.0.0"]],
        installed: [["demo/a", "1.0.0"], ["demo/b", "2.0.0"], ["demo/stray", "9.9.9"]]
      )

      config = RubySkills::Config.new(root: root)
      expect(plan.artifacts.map(&:name)).to eq(["demo/a"])
      expect(RubySkills::Install.installed?("demo/stray", "9.9.9", config: config)).to be true
    end
  end

  it "keeps a skill reachable only through resolved dependencies" do
    with_tmp_project do |root|
      child = RubySkills::Dependency.new(
        name: "demo/child",
        requirement: Gem::Requirement.default
      )
      parent = resolved("demo/b", "2.0.0")
      parent.instance_variable_set(:@dependencies, [child])
      nested = resolved("demo/child", "0.1.0")
      plant(root, "demo/a", "1.0.0")
      plant(root, "demo/child", "0.1.0")
      plan = described_class.new(
        removed_name: "demo/a",
        skillfile: skillfile_with(dep("demo/b")),
        lockfile: lockfile_with(
          locked("demo/a", "1.0.0"),
          locked("demo/b", "2.0.0"),
          locked("demo/child", "0.1.0")
        ),
        resolution: RubySkills::Resolution.new(
          source: "https://rubyskills.org",
          skills: [parent, nested],
          dependencies: [dep("demo/b")]
        ),
        config: RubySkills::Config.new(root: root)
      ).plan

      expect(plan.required_names).to include("demo/b", "demo/child")
      expect(plan.artifacts.map(&:name)).to eq(["demo/a"])
    end
  end
end
