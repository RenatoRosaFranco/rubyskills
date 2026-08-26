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

RSpec.describe RubySkills::Adapters do
  describe ".all" do
    it "lists the built-in agent adapters" do
      expect(described_class.all).to eq(
        [
          RubySkills::Adapters::Claude,
          RubySkills::Adapters::Codex,
          RubySkills::Adapters::Cursor,
          RubySkills::Adapters::Vscode
        ]
      )
    end
  end

  describe ".sync_remove" do
    it "removes the skill from every adapter destination" do
      with_tmp_project do |root|
        destinations = described_class.all.map { |klass|
          info = klass::ADAPTER_INFO
          path = root.join(info.fetch(:adapter), info.fetch(:directory), "rails-performance")
          FileUtils.mkdir_p(path)
          path.join("SKILL.md").write("# skill\n")
          path
        }

        described_class.sync_remove("rails-performance", root: root)

        expect(destinations.map(&:exist?)).to all(be false)
      end
    end
  end
end
