# frozen_string_literal: true

require "digest"

RSpec.describe RubySkills::Artifact::Reader do
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

  def build_from(root, yaml: valid_yaml, files: { "SKILL.md" => "# skill\n" })
    dir = write_skill(root, yaml: yaml, files: files)
    manifest = RubySkills::Manifest.load(dir)
    RubySkills::Artifact::Builder.new(
      root: dir,
      manifest: manifest,
      destination: root
    ).build
  end

  def write_bytes(root, bytes, name: "artifact.rskill")
    path = root.join(name)
    path.binwrite(bytes)
    path
  end

  def expect_not_to_open_archive
    allow(Zlib::GzipReader).to receive(:new)
    yield
    expect(Zlib::GzipReader).not_to have_received(:new)
  end

  describe "#checksum" do
    it "hashes the raw .rskill bytes without unpacking" do
      with_tmp_project do |root|
        result = build_from(root)

        artifact = described_class.new(result.path)

        expect_not_to_open_archive do
          expect(artifact.checksum).to eq(Digest::SHA256.file(result.path).hexdigest)
          expect(artifact.checksum).to eq(result.checksum)
        end
      end
    end
  end

  describe "#valid?" do
    it "is true when the downloaded SHA-256 matches the registry SHA-256" do
      with_tmp_project do |root|
        result = build_from(root)
        artifact = described_class.new(
          result.path,
          expected_checksum: result.checksum
        )

        expect(artifact).to be_valid
        expect(artifact.manifest).to be_valid
        expect(artifact.manifest.full_name).to eq("rails/request-specs")
        expect(artifact.files.keys).to include("skill.yml", "SKILL.md")
      end
    end

    it "accepts an uppercase registry checksum" do
      with_tmp_project do |root|
        result = build_from(root)
        artifact = described_class.new(
          result.path,
          expected_checksum: result.checksum.upcase
        )

        expect(artifact).to be_valid
      end
    end

    it "is false when the downloaded SHA-256 does not match the registry" do
      with_tmp_project do |root|
        result = build_from(root)
        artifact = described_class.new(result.path, expected_checksum: "a" * 64)

        expect_not_to_open_archive do
          expect(artifact).not_to be_valid
        end
      end
    end

    it "is false for matching bytes that are not a skill archive" do
      with_tmp_project do |root|
        path = write_bytes(root, "not-a-gzip")
        artifact = described_class.new(
          path,
          expected_checksum: Digest::SHA256.file(path).hexdigest
        )

        expect(artifact).not_to be_valid
      end
    end

    it "is false when skill.yml is missing from the archive" do
      with_tmp_project do |root|
        bytes = RubySkills::Artifact::Archive.pack([["README.md", "# hi\n"]])
        path = write_bytes(root, bytes)
        artifact = described_class.new(
          path,
          expected_checksum: Digest::SHA256.hexdigest(bytes)
        )

        expect(artifact).not_to be_valid
      end
    end
  end

  describe "#files" do
    it "returns archive members after the checksum matches" do
      with_tmp_project do |root|
        result = build_from(
          root,
          files: {
            "SKILL.md" => "# skill\n",
            "references/http.md" => "# http\n"
          }
        )
        artifact = described_class.new(
          result.path,
          expected_checksum: result.checksum
        )

        expect(artifact.files["SKILL.md"]).to eq("# skill\n")
        expect(artifact.files["references/http.md"]).to eq("# http\n")
      end
    end

    it "does not unpack when the checksum does not match" do
      with_tmp_project do |root|
        result = build_from(root)
        artifact = described_class.new(result.path, expected_checksum: "a" * 64)

        expect_not_to_open_archive do
          expect { artifact.files }.to raise_error(
            RubySkills::Error,
            "Checksum mismatch"
          )
        end
      end
    end
  end

  describe "#manifest" do
    it "loads skill.yml from the archive without extracting" do
      with_tmp_project do |root|
        result = build_from(root)
        dest = root.join("unpacked")
        artifact = described_class.new(
          result.path,
          expected_checksum: result.checksum
        )

        expect(artifact.manifest.full_name).to eq("rails/request-specs")
        expect(dest).not_to exist
      end
    end
  end

  describe "#extract_to" do
    it "extracts after the downloaded SHA-256 matches the registry SHA-256" do
      with_tmp_project do |root|
        result = build_from(
          root,
          files: {
            "SKILL.md" => "# skill\n",
            "references/http.md" => "# http\n"
          }
        )
        dest = root.join("unpacked")
        artifact = described_class.new(
          result.path,
          expected_checksum: result.checksum
        )

        unpacked = artifact.extract_to(dest)
        manifest = RubySkills::Manifest.load(unpacked)

        expect(unpacked.join("SKILL.md").read).to eq("# skill\n")
        expect(unpacked.join("references/http.md").read).to eq("# http\n")
        expect(manifest).to be_valid
      end
    end

    it "does not extract when the checksum does not match" do
      with_tmp_project do |root|
        result = build_from(root)
        dest = root.join("unpacked")
        artifact = described_class.new(result.path, expected_checksum: "a" * 64)

        expect_not_to_open_archive do
          expect { artifact.extract_to(dest) }.to raise_error(
            RubySkills::Error,
            "Checksum mismatch"
          )
        end
        expect(dest).not_to exist
      end
    end

    it "does not overwrite an existing destination on checksum mismatch" do
      with_tmp_project do |root|
        result = build_from(root)
        dest = root.join("unpacked")
        dest.mkpath
        dest.join("keep.txt").write("keep\n")
        artifact = described_class.new(result.path, expected_checksum: "a" * 64)

        expect { artifact.extract_to(dest) }.to raise_error(
          RubySkills::Error,
          "Checksum mismatch"
        )
        expect(dest.join("keep.txt").read).to eq("keep\n")
        expect(dest.join("skill.yml")).not_to exist
      end
    end

    it "rejects archive members that escape the destination" do
      with_tmp_project do |root|
        bytes = RubySkills::Artifact::Archive.pack([["../evil", "pwned\n"]])
        path = write_bytes(root, bytes)
        dest = root.join("unpacked")
        artifact = described_class.new(
          path,
          expected_checksum: Digest::SHA256.hexdigest(bytes)
        )

        expect { artifact.extract_to(dest) }.to raise_error(
          RubySkills::Error,
          "../evil escapes the skill directory"
        )
        expect(root.join("evil")).not_to exist
        expect(dest).not_to exist
      end
    end
  end
end
