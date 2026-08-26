# frozen_string_literal: true

RSpec.describe RubySkills::Resolver do
  describe "#resolve" do
    it "resolves a local skill directory" do
      with_tmp_project do |root|
        skill_dir = root.join("skills", "rails-performance")
        FileUtils.mkdir_p(skill_dir)
        skill_dir.join("SKILL.md").write("# skill\n")

        skill = RubySkills::LegacySkillfile::Skill.new(
          name: "rails-performance",
          path: skill_dir.to_s
        )

        resolved = described_class.new.resolve(skill)

        expect(resolved).to have_attributes(
          name: "rails-performance",
          path: skill_dir.expand_path,
          source: "path:#{skill_dir.expand_path}"
        )
      end
    end

    it "raises when the local path is not a directory" do
      with_tmp_project do |root|
        skill = RubySkills::LegacySkillfile::Skill.new(
          name: "missing",
          path: root.join("does-not-exist").to_s
        )

        expect {
          described_class.new.resolve(skill)
        }.to raise_error(RubySkills::Error, /Skill path does not exist/)
      end
    end

    it "raises when the skill has no usable source" do
      skill = RubySkills::LegacySkillfile::Skill.new(name: "orphan")

      expect {
        described_class.new.resolve(skill)
      }.to raise_error(RubySkills::Error, "Unable to resolve orphan")
    end
  end
end
