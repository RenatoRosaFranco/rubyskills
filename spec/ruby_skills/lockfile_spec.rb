# frozen_string_literal: true

RSpec.describe RubySkills::Lockfile do
  def lockfile_for(root)
    described_class.new(config: RubySkills::Config.new(root: root))
  end

  describe "#skills" do
    it "returns an empty hash when Skills.lock is missing" do
      with_tmp_project do |root|
        expect(lockfile_for(root).skills).to eq({})
      end
    end

    it "reads installed skills from Skills.lock" do
      with_tmp_project do |root|
        root.join("Skills.lock").write(
          YAML.dump(
            "version" => 1,
            "skills" => {
              "rails-performance" => {
                "version" => "0.1.0",
                "source" => "github:username/rails-performance"
              }
            }
          )
        )

        expect(lockfile_for(root).skills).to eq(
          "rails-performance" => {
            "version" => "0.1.0",
            "source" => "github:username/rails-performance"
          }
        )
      end
    end

    it "returns an empty hash when the lockfile has no skills key" do
      with_tmp_project do |root|
        root.join("Skills.lock").write(YAML.dump("version" => 1))

        expect(lockfile_for(root).skills).to eq({})
      end
    end
  end

  describe "#add" do
    it "creates Skills.lock and records the skill" do
      with_tmp_project do |root|
        lockfile_for(root).add(
          "rails-security",
          version: "0.2.0",
          source: "github:username/rails-security"
        )

        data = YAML.safe_load_file(root.join("Skills.lock"))

        expect(data["version"]).to eq(1)
        expect(data["skills"]["rails-security"]).to eq(
          "version" => "0.2.0",
          "source" => "github:username/rails-security"
        )
      end
    end

    it "keeps previously installed skills" do
      with_tmp_project do |root|
        lockfile = lockfile_for(root)
        lockfile.add("alpha", version: "1.0.0", source: "path:/tmp/alpha")
        lockfile.add("beta", version: "2.0.0", source: "path:/tmp/beta")

        expect(lockfile.skills.keys).to contain_exactly("alpha", "beta")
      end
    end
  end

  describe "#remove" do
    it "drops the skill from Skills.lock" do
      with_tmp_project do |root|
        lockfile = lockfile_for(root)
        lockfile.add("alpha", version: "1.0.0", source: "path:/tmp/alpha")
        lockfile.add("beta", version: "2.0.0", source: "path:/tmp/beta")

        lockfile.remove("alpha")

        expect(lockfile.skills.keys).to eq(["beta"])
      end
    end
  end
end
