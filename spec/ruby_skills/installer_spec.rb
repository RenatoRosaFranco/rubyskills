# frozen_string_literal: true

RSpec.describe RubySkills::Installer do
  let(:skill) do
    RubySkills::Skillfile::Skill.new(
      name: "rails-performance",
      path: "/tmp/rails-performance",
      version: "0.1.0"
    )
  end

  let(:manifest) do
    instance_double(RubySkills::Skillfile, skills: [skill]).tap do |double|
      allow(double).to receive(:load!).and_return(double)
    end
  end

  before do
    allow(RubySkills::Skillfile).to receive(:new).and_return(manifest)
  end

  describe "#install" do
    it "raises when the named skill is not in the Skillfile" do
      with_tmp_project do |root|
        installer = described_class.new(
          config: RubySkills::Config.new(root: root)
        )

        expect {
          installer.install("missing")
        }.to raise_error(
          RubySkills::Error,
          "Skill `missing` is not in the Skillfile"
        )
      end
    end

    it "resolves, copies, notifies adapters, and locks the skill" do
      with_tmp_project do |root|
        source = root.join("source-skill")
        FileUtils.mkdir_p(source)
        source.join("SKILL.md").write("# rails-performance\n")

        resolved = RubySkills::Resolver::ResolvedSkill.new(
          name: "rails-performance",
          path: source,
          source: "path:#{source}"
        )

        adapter = instance_double(RubySkills::Adapters::Claude)
        allow(RubySkills::Resolver).to receive(:new)
          .and_return(instance_double(RubySkills::Resolver, resolve: resolved))
        allow(RubySkills::Adapters::Claude).to receive(:new).and_return(adapter)
        allow(RubySkills::Adapters::Codex).to receive(:new).and_return(adapter)
        allow(RubySkills::Adapters::Cursor).to receive(:new).and_return(adapter)
        allow(RubySkills::Adapters::Vscode).to receive(:new).and_return(adapter)
        allow(adapter).to receive(:install)

        installer = described_class.new(
          config: RubySkills::Config.new(root: root)
        )

        expect {
          installer.install("rails-performance")
        }.to output(/Installed rails-performance/).to_stdout

        destination = root.join(".ruby-skills", "rails-performance")
        expect(destination.join("SKILL.md")).to be_file
        expect(adapter).to have_received(:install)
          .with("rails-performance", destination)
          .at_least(:once)

        lock = RubySkills::Lockfile.new(
          config: RubySkills::Config.new(root: root)
        )
        expect(lock.skills["rails-performance"]).to include(
          "version" => "0.1.0",
          "source" => "path:#{source}"
        )
      end
    end
  end
end
