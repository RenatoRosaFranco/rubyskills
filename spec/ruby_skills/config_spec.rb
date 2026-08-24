# frozen_string_literal: true

RSpec.describe RubySkills::Config do
  describe "#skillfile_path" do
    it "resolves Skillfile under the given root" do
      config = described_class.new(root: "/tmp/project")

      expect(config.skillfile_path.to_s).to eq("/tmp/project/Skillfile")
    end
  end

  describe "#lockfile_path" do
    it "resolves Skills.lock under the given root" do
      config = described_class.new(root: "/tmp/project")

      expect(config.lockfile_path.to_s).to eq("/tmp/project/Skills.lock")
    end
  end

  describe "#skills_path" do
    it "resolves .ruby-skills under the given root" do
      config = described_class.new(root: "/tmp/project")

      expect(config.skills_path.to_s).to eq("/tmp/project/.ruby-skills")
    end
  end

  describe "#initialize_project!" do
    it "creates the skills directory and a starter Skillfile" do
      with_tmp_project do |root|
        described_class.new(root: root).initialize_project!

        expect(root.join(".ruby-skills")).to be_directory
        expect(root.join("Skillfile")).to be_file
        expect(root.join("Skillfile").read).to include("Ruby Skills")
      end
    end

    it "does not overwrite an existing Skillfile" do
      with_tmp_project do |root|
        root.join("Skillfile").write("# keep me\n")

        described_class.new(root: root).initialize_project!

        expect(root.join("Skillfile").read).to eq("# keep me\n")
      end
    end
  end
end
