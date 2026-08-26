# frozen_string_literal: true

RSpec.describe RubySkills::Validator do
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

  describe "#validate" do
    it "accepts a valid skill directory" do
      with_tmp_project do |root|
        dir = write_skill(
          root,
          yaml: valid_yaml,
          files: {
            "SKILL.md" => "# skill\n",
            "references/http.md" => "# http\n",
            "references/status.md" => "# status\n"
          }
        )

        result = described_class.new(dir).validate

        expect(result).to be_valid
        expect(result.label).to eq("rails/request-specs 0.1.0")
        expect(result.file_count).to eq(3)
      end
    end

    it "collects multiple failures at once" do
      with_tmp_project do |root|
        dir = write_skill(
          root,
          yaml: valid_yaml(
            "version" => "foo",
            "entrypoint" => "SKILL.md",
            "files" => ["../secret"]
          ),
          files: {}
        )

        result = described_class.new(dir).validate

        expect(result).not_to be_valid
        expect(result.failures).to include(
          %(version: "foo" is invalid),
          "entrypoint: SKILL.md does not exist",
          "files: ../secret escapes the skill directory"
        )
      end
    end

    it "returns a skill.yml load error without mutating files" do
      with_tmp_project do |root|
        dir = root.join("empty")
        FileUtils.mkdir_p(dir)

        result = described_class.new(dir).validate

        expect(result).not_to be_valid
        expect(result.label).to eq("skill")
        expect(result.failures.first).to match(/skill.yml not found/)
        expect(dir.children).to be_empty
      end
    end
  end
end
