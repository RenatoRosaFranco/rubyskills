# frozen_string_literal: true

RSpec.describe RubySkills::Generators::Skill do
  describe "#create" do
    it "scaffolds skill.yml, SKILL.md and references/" do
      with_tmp_project do |root|
        result = described_class.new(root: root).create("rails/request-specs")
        destination = root.join("request-specs")

        expect(result).to have_attributes(
          name: "request-specs",
          namespace: "rails",
          in_place: false,
          directory: destination
        )
        expect(destination.join("skill.yml")).to be_file
        expect(destination.join("SKILL.md")).to be_file
        expect(destination.join("references")).to be_directory
      end
    end

    it "writes a valid starter manifest" do
      with_tmp_project do |root|
        described_class.new(root: root).create("rails/request-specs")
        manifest = RubySkills::Manifest.load(root.join("request-specs"))

        expect(manifest).to be_valid
        expect(manifest).to have_attributes(
          name: "request-specs",
          namespace: "rails",
          version: "0.1.0",
          summary: "TODO",
          entrypoint: "SKILL.md",
          files: ["SKILL.md", "references/**"]
        )
      end
    end

    it "writes a titled SKILL.md" do
      with_tmp_project do |root|
        described_class.new(root: root).create("rails/request-specs")

        expect(root.join("request-specs", "SKILL.md").read).to include(
          "# Rails Request Specs",
          "## Purpose",
          "## Guidance"
        )
      end
    end

    it "creates files in place when requested" do
      with_tmp_project do |root|
        described_class.new(root: root).create("rails/request-specs", in_place: true)

        expect(root.join("skill.yml")).to be_file
        expect(root.join("SKILL.md")).to be_file
        expect(root.join("references")).to be_directory
        expect(root.join("request-specs")).not_to exist
      end
    end

    it "refuses to overwrite an existing directory" do
      with_tmp_project do |root|
        root.join("request-specs").mkdir

        expect {
          described_class.new(root: root).create("rails/request-specs")
        }.to raise_error(
          RubySkills::Error,
          "Directory already exists: request-specs"
        )
      end
    end

    it "rejects a name that is not namespace/name" do
      with_tmp_project do |root|
        expect {
          described_class.new(root: root).create("request-specs")
        }.to raise_error(RubySkills::Error, %r{namespace/name})
      end
    end

    it "rejects an invalid identifier" do
      with_tmp_project do |root|
        expect {
          described_class.new(root: root).create("Rails/Request Specs")
        }.to raise_error(RubySkills::Error, /must be lowercase/)
      end
    end
  end
end
