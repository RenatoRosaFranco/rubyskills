# frozen_string_literal: true

RSpec.describe RubySkills::Manifest do
  def valid_yaml
    <<~YAML
      name: request-specs
      namespace: rails
      version: 0.1.0

      summary: >
        Practices for writing request specs in Rails applications.

      description: >
        Ruby/Rails-specific knowledge for coding agents working
        with HTTP behavior and request specs.

      categories:
        - testing

      tags:
        - rails
        - rspec

      entrypoint: SKILL.md

      compatibility:
        ruby: ">= 3.2"
        rails: ">= 7.1"

      files:
        - SKILL.md
        - references/**
    YAML
  end

  def write_skill(root, yaml:, files: { "SKILL.md" => "# request specs\n" })
    dir = root.join("my-skill")
    FileUtils.mkdir_p(dir)

    files.each do |relative, contents|
      path = dir.join(relative)
      FileUtils.mkdir_p(path.dirname)
      path.write(contents)
    end

    dir.join("skill.yml").write(yaml) if yaml
    dir
  end

  def load_skill(root, yaml:, files: { "SKILL.md" => "# request specs\n" })
    described_class.load(write_skill(root, yaml: yaml, files: files))
  end

  describe ".load" do
    it "loads a valid skill.yml from a skill directory" do
      with_tmp_project do |root|
        manifest = load_skill(root, yaml: valid_yaml)

        expect(manifest).to be_valid
        expect(manifest).to have_attributes(
          name: "request-specs",
          namespace: "rails",
          version: "0.1.0",
          entrypoint: "SKILL.md",
          categories: ["testing"],
          tags: %w[rails rspec]
        )
        expect(manifest.full_name).to eq("rails/request-specs")
      end
    end

    it "exposes summary, description, compatibility and files" do
      with_tmp_project do |root|
        manifest = load_skill(root, yaml: valid_yaml)

        expect(manifest.summary).to include("request specs")
        expect(manifest.description).to include("HTTP behavior")
        expect(manifest.compatibility).to eq(
          "ruby" => ">= 3.2",
          "rails" => ">= 7.1"
        )
        expect(manifest.files).to eq(["SKILL.md", "references/**"])
      end
    end

    it "loads from a skill.yml file path" do
      with_tmp_project do |root|
        dir = write_skill(root, yaml: valid_yaml)
        manifest = described_class.load(dir.join("skill.yml"))

        expect(manifest).to be_valid
        expect(manifest.name).to eq("request-specs")
      end
    end

    it "defaults optional collections when they are omitted" do
      with_tmp_project do |root|
        yaml = <<~YAML
          name: request-specs
          namespace: rails
          version: 0.1.0
          summary: Practices for writing request specs.
          entrypoint: SKILL.md
        YAML

        manifest = load_skill(root, yaml: yaml)

        expect(manifest).to be_valid
        expect(manifest.description).to be_nil
        expect(manifest.categories).to eq([])
        expect(manifest.tags).to eq([])
        expect(manifest.compatibility).to eq({})
        expect(manifest.files).to eq(["SKILL.md"])
      end
    end

    it "returns a hash snapshot from #to_h" do
      with_tmp_project do |root|
        manifest = load_skill(root, yaml: valid_yaml)

        expect(manifest.to_h).to include(
          "name" => "request-specs",
          "namespace" => "rails",
          "full_name" => "rails/request-specs",
          "entrypoint" => "SKILL.md"
        )
      end
    end

    it "raises when the skill path does not exist" do
      expect {
        described_class.load("/tmp/ruby-skills-missing-skill")
      }.to raise_error(RubySkills::Error, /Skill path does not exist/)
    end

    it "raises when skill.yml is missing" do
      with_tmp_project do |root|
        dir = root.join("empty-skill")
        FileUtils.mkdir_p(dir)

        expect {
          described_class.load(dir)
        }.to raise_error(RubySkills::Error, /skill.yml not found/)
      end
    end

    it "raises when skill.yml is not safe YAML" do
      with_tmp_project do |root|
        yaml = <<~YAML
          a: &shared
            x: 1
          b: *shared
        YAML

        expect {
          load_skill(root, yaml: yaml)
        }.to raise_error(RubySkills::Error, /Invalid skill.yml/)
      end
    end
  end

  describe "validation" do
    it "rejects missing required fields" do
      with_tmp_project do |root|
        manifest = load_skill(root, yaml: "{}\n")

        expect(manifest).not_to be_valid
        expect(manifest.errors).to include(
          "name is required",
          "namespace is required",
          "version is required",
          "summary is required",
          "entrypoint is required"
        )
      end
    end

    it "rejects invalid name and namespace identifiers" do
      with_tmp_project do |root|
        yaml = <<~YAML
          name: Request Specs
          namespace: Rails/Core
          version: 0.1.0
          summary: Invalid identifiers.
          entrypoint: SKILL.md
        YAML

        manifest = load_skill(root, yaml: yaml)

        expect(manifest).not_to be_valid
        expect(manifest.errors).to include(
          a_string_matching(/name must be lowercase/),
          a_string_matching(/namespace must be lowercase/)
        )
      end
    end

    it "rejects an invalid version" do
      with_tmp_project do |root|
        yaml = <<~YAML
          name: request-specs
          namespace: rails
          version: not-a-version
          summary: Invalid version.
          entrypoint: SKILL.md
        YAML

        manifest = load_skill(root, yaml: yaml)

        expect(manifest).not_to be_valid
        expect(manifest.errors).to include("version is not a valid gem version")
      end
    end

    it "rejects a blank summary" do
      with_tmp_project do |root|
        yaml = <<~YAML
          name: request-specs
          namespace: rails
          version: 0.1.0
          summary: "   "
          entrypoint: SKILL.md
        YAML

        manifest = load_skill(root, yaml: yaml)

        expect(manifest).not_to be_valid
        expect(manifest.errors).to include("summary is required")
      end
    end

    it "rejects an absolute entrypoint" do
      with_tmp_project do |root|
        yaml = <<~YAML
          name: request-specs
          namespace: rails
          version: 0.1.0
          summary: Absolute entrypoint.
          entrypoint: /etc/passwd
        YAML

        manifest = load_skill(root, yaml: yaml)

        expect(manifest).not_to be_valid
        expect(manifest.errors).to include("entrypoint must be a relative path")
      end
    end

    it "rejects path traversal in the entrypoint" do
      with_tmp_project do |root|
        yaml = <<~YAML
          name: request-specs
          namespace: rails
          version: 0.1.0
          summary: Traversal entrypoint.
          entrypoint: ../SKILL.md
        YAML

        manifest = load_skill(root, yaml: yaml)

        expect(manifest).not_to be_valid
        expect(manifest.errors).to include(
          "entrypoint must not contain path traversal"
        )
      end
    end

    it "rejects a missing entrypoint file" do
      with_tmp_project do |root|
        yaml = <<~YAML
          name: request-specs
          namespace: rails
          version: 0.1.0
          summary: Missing entrypoint file.
          entrypoint: missing.md
        YAML

        manifest = load_skill(root, yaml: yaml)

        expect(manifest).not_to be_valid
        expect(manifest.errors).to include(
          "entrypoint file does not exist: missing.md"
        )
      end
    end

    it "rejects non-array categories and tags" do
      with_tmp_project do |root|
        yaml = <<~YAML
          name: request-specs
          namespace: rails
          version: 0.1.0
          summary: Bad collections.
          entrypoint: SKILL.md
          categories: testing
          tags: rails
        YAML

        manifest = load_skill(root, yaml: yaml)

        expect(manifest).not_to be_valid
        expect(manifest.errors).to include(
          "categories must be an array of strings",
          "tags must be an array of strings"
        )
      end
    end
  end
end
