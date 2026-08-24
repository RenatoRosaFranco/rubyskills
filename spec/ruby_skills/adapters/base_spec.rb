# frozen_string_literal: true

RSpec.describe RubySkills::Adapters::Claude do
  describe "#remove" do
    it "deletes the skill directory under .claude/skills" do
      with_tmp_project do |root|
        destination = root.join(".claude", "skills", "rails-performance")
        FileUtils.mkdir_p(destination)
        destination.join("SKILL.md").write("# skill\n")

        described_class.new(root: root).remove("rails-performance")

        expect(destination).not_to exist
      end
    end
  end
end

RSpec.describe RubySkills::Adapters::Cursor do
  it "uses .cursor/skills as the adapter destination" do
    expect(described_class::ADAPTER_INFO).to eq(
      adapter: ".cursor",
      directory: "skills"
    )
  end
end

RSpec.describe RubySkills::Adapters::Vscode do
  it "uses .vscode/skills as the adapter destination" do
    expect(described_class::ADAPTER_INFO).to eq(
      adapter: ".vscode",
      directory: "skills"
    )
  end
end

RSpec.describe RubySkills::Adapters::Codex do
  it "uses .codex/skills as the adapter destination" do
    expect(described_class::ADAPTER_INFO).to eq(
      adapter: ".codex",
      directory: "skills"
    )
  end
end
