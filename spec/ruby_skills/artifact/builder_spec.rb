# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::Artifact::Builder do
  def write_skill(root, yaml:, files: { "SKILL.md" => "# skill\n" })
    dir = root.join("request-specs")
    FileUtils.mkdir_p(dir.join("references"))

    files.each do |relative, contents|
      path = dir.join(relative)
      FileUtils.mkdir_p(path.dirname)
      path.write(contents)
    end

    dir.join("skill.yml").write(yaml)
    dir
  end

  def valid_yaml(overrides = {})
    {
      "name" => "request-specs",
      "namespace" => "rails",
      "version" => "0.1.0",
      "summary" => "Request specs.",
      "entrypoint" => "SKILL.md",
      "files" => ["SKILL.md", "references/**"]
    }.merge(overrides).to_yaml
  end

  def build_from(dir, destination: nil)
    manifest = RubySkills::Manifest.load(dir)
    described_class.new(
      root: dir,
      manifest: manifest,
      destination: destination || dir.parent
    ).build
  end

  describe "#build" do
    it "packages skill.yml, the entrypoint and glob matches as a .rskill" do
      with_tmp_project do |root|
        dir = write_skill(
          root,
          yaml: valid_yaml,
          files: {
            "SKILL.md" => "# skill\n",
            "references/http.md" => "# http\n",
            "references/status.md" => "# status\n",
            "ignored.txt" => "nope\n"
          }
        )

        result = build_from(dir)

        expect(result.path.basename.to_s).to eq("rails-request-specs-0.1.0.rskill")
        expect(result.path).to be_file
        expect(result.size).to eq(result.path.size)
        expect(result.checksum).to eq(Digest::SHA256.file(result.path).hexdigest)
        expect(result.files).to eq(
          %w[SKILL.md references/http.md references/status.md skill.yml]
        )
        expect(result.files).not_to include("ignored.txt")
      end
    end

    it "deduplicates overlapping globs and the required files" do
      with_tmp_project do |root|
        dir = write_skill(
          root,
          yaml: valid_yaml(
            "files" => ["SKILL.md", "SKILL.md", "**/*.md", "references/**"]
          ),
          files: {
            "SKILL.md" => "# skill\n",
            "references/http.md" => "# http\n"
          }
        )

        result = build_from(dir)

        expect(result.files).to eq(%w[SKILL.md references/http.md skill.yml])
      end
    end

    it "produces byte-identical artifacts for the same skill" do
      with_tmp_project do |root|
        dir = write_skill(
          root,
          yaml: valid_yaml,
          files: {
            "SKILL.md" => "# skill\n",
            "references/http.md" => "# http\n"
          }
        )

        first = build_from(dir, destination: root.join("a"))
        File.utime(Time.now + 3_600, Time.now + 3_600, dir.join("SKILL.md"))
        second = build_from(dir, destination: root.join("b"))

        expect(second.path.binread).to eq(first.path.binread)
        expect(second.checksum).to eq(first.checksum)
      end
    end

    it "changes the checksum when file contents change" do
      with_tmp_project do |root|
        dir = write_skill(root, yaml: valid_yaml)

        original = build_from(dir, destination: root.join("a"))
        dir.join("SKILL.md").write("# changed\n")
        changed = build_from(dir, destination: root.join("b"))

        expect(changed.checksum).not_to eq(original.checksum)
        expect(changed.path.binread).not_to eq(original.path.binread)
      end
    end

    it "rejects path traversal in files" do
      with_tmp_project do |root|
        root.join("secret").write("nope\n")
        dir = write_skill(root, yaml: valid_yaml("files" => ["SKILL.md", "../secret"]))

        expect { build_from(dir) }.to raise_error(
          RubySkills::Error,
          "../secret escapes the skill directory"
        )
      end
    end

    it "rejects absolute paths in files" do
      with_tmp_project do |root|
        secret = root.join("secret")
        secret.write("nope\n")
        dir = write_skill(root, yaml: valid_yaml("files" => ["SKILL.md", secret.to_s]))

        expect { build_from(dir) }.to raise_error(
          RubySkills::Error,
          /must be a relative path/
        )
      end
    end

    it "rejects unsafe symlinks" do
      with_tmp_project do |root|
        secret = root.join("secret")
        secret.write("nope\n")
        dir = write_skill(
          root,
          yaml: valid_yaml("files" => ["SKILL.md", "leak.md"])
        )
        File.symlink(secret, dir.join("leak.md"))

        expect { build_from(dir) }.to raise_error(
          RubySkills::Error,
          "leak.md is an unsafe symlink"
        )
      end
    end

    it "includes safe symlinks that stay inside the skill root" do
      with_tmp_project do |root|
        dir = write_skill(
          root,
          yaml: valid_yaml("files" => ["SKILL.md", "alias.md"]),
          files: { "SKILL.md" => "# skill\n" }
        )
        File.symlink("SKILL.md", dir.join("alias.md"))

        result = build_from(dir)
        extracted = RubySkills::Artifact::Reader.new(result.path).files

        expect(result.files).to include("alias.md", "SKILL.md")
        expect(extracted["alias.md"]).to eq("# skill\n")
      end
    end

    it "can be read back successfully" do
      with_tmp_project do |root|
        dir = write_skill(
          root,
          yaml: valid_yaml,
          files: {
            "SKILL.md" => "# skill\n",
            "references/http.md" => "# http\n"
          }
        )

        result = build_from(dir)
        unpacked = RubySkills::Artifact::Reader.new(result.path).extract_to(
          root.join("unpacked")
        )
        manifest = RubySkills::Manifest.load(unpacked)

        expect(unpacked.join("skill.yml").read).to eq(dir.join("skill.yml").read)
        expect(unpacked.join("SKILL.md").read).to eq("# skill\n")
        expect(unpacked.join("references/http.md").read).to eq("# http\n")
        expect(manifest).to be_valid
        expect(manifest.full_name).to eq("rails/request-specs")
      end
    end
  end
end
