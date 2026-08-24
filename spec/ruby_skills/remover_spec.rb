# frozen_string_literal: true

RSpec.describe RubySkills::Remover do
  describe "#remove" do
    it "raises when the skill is not installed" do
      with_tmp_project do |root|
        remover = described_class.new(
          config: RubySkills::Config.new(root: root)
        )

        expect {
          remover.remove("missing")
        }.to raise_error(
          RubySkills::Error,
          "Skill `missing` is not installed"
        )
      end
    end

    it "deletes the installed skill directory and lockfile entry" do
      with_tmp_project do |root|
        config = RubySkills::Config.new(root: root)
        skill_path = config.skills_path.join("rails-performance")
        FileUtils.mkdir_p(skill_path)
        skill_path.join("SKILL.md").write("# skill\n")

        RubySkills::Lockfile.new(config: config).add(
          "rails-performance",
          version: "0.1.0",
          source: "path:#{skill_path}"
        )

        remover = described_class.new(config: config)
        allow(remover).to receive(:adapters).and_return([])

        expect {
          remover.remove("rails-performance")
        }.to output(/Removed rails-performance/).to_stdout

        expect(skill_path).not_to exist
        expect(RubySkills::Lockfile.new.skills).not_to have_key("rails-performance")
      end
    end
  end
end
