# frozen_string_literal: true

RSpec.describe RubySkills::Skillfile do
  def write_skillfile(root, contents)
    path = root.join("Skillfile")
    path.write(contents)
    path
  end

  describe "#load!" do
    it "parses skill declarations from the Skillfile" do
      with_tmp_project do |root|
        path = write_skillfile(
          root,
          <<~RUBY
            skill "rails-performance", github: "username/rails-performance"
            skill "local-review", path: "../skills/local-review", version: "0.1.0"
          RUBY
        )

        skills = described_class.new(path: path).load!.skills

        expect(skills.size).to eq(2)
        expect(skills.first).to have_attributes(
          name: "rails-performance",
          github: "username/rails-performance",
          path: nil,
          version: nil
        )
        expect(skills.last).to have_attributes(
          name: "local-review",
          github: nil,
          path: "../skills/local-review",
          version: "0.1.0"
        )
      end
    end

    it "loads the Skillfile from the project root by default" do
      with_tmp_project do |root|
        write_skillfile(root, 'skill "from-root", path: "./skill"')

        skills = described_class.new.load!.skills

        expect(skills.first).to have_attributes(name: "from-root", path: "./skill")
      end
    end

    it "raises when the Skillfile is missing" do
      with_tmp_project do |root|
        expect {
          described_class.new(path: root.join("Skillfile")).load!
        }.to raise_error(
          RubySkills::Error,
          "Skillfile not found. Run `ruby-skills init` first."
        )
      end
    end

    it "raises when the Skillfile is invalid Ruby" do
      with_tmp_project do |root|
        path = write_skillfile(root, "skill (")

        expect {
          described_class.new(path: path).load!
        }.to raise_error(RubySkills::Error, /Invalid Skillfile/)
      end
    end

    it "raises when a skill has neither github nor path" do
      with_tmp_project do |root|
        path = write_skillfile(root, 'skill "broken"')

        expect {
          described_class.new(path: path).load!
        }.to raise_error(
          RubySkills::Error,
          "broken: either github or path: must be provided"
        )
      end
    end
  end
end
