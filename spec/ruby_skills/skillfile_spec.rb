# frozen_string_literal: true

RSpec.describe RubySkills::Skillfile do
  def write_skillfile(root, contents)
    path = root.join("Skillfile")
    path.write(contents)
    path
  end

  def load_skillfile(root, contents, **options)
    described_class.load(write_skillfile(root, contents), **options)
  end

  describe ".load" do
    it "parses a valid Skillfile with an explicit source and constraints" do
      with_tmp_project do |root|
        skillfile = load_skillfile(
          root,
          <<~RUBY
            source "https://rubyskills.org"

            skill "rails/conventions", "~> 1.0"
            skill "rails/request-specs", "~> 2.1"
          RUBY
        )

        expect(skillfile.source).to eq("https://rubyskills.org")
        expect(skillfile.dependencies.size).to eq(2)
        expect(skillfile.find("rails/request-specs")).to have_attributes(
          name: "rails/request-specs",
          requirement: Gem::Requirement.new("~> 2.1")
        )
        expect(skillfile.include?("rails/conventions")).to be true
        expect(skillfile.to_h).to eq(
          source: "https://rubyskills.org",
          dependencies: [
            { name: "rails/conventions", requirement: "~> 1.0" },
            { name: "rails/request-specs", requirement: "~> 2.1" }
          ]
        )
      end
    end

    it "accepts skills without a version constraint as >= 0" do
      with_tmp_project do |root|
        skillfile = load_skillfile(root, 'skill "ruby/gem-development"')
        dependency = skillfile.find("ruby/gem-development")

        expect(dependency.requirement).to eq(Gem::Requirement.new(">= 0"))
        expect(skillfile.to_h[:dependencies]).to eq(
          [{ name: "ruby/gem-development", requirement: ">= 0" }]
        )
      end
    end

    it "uses the configured registry when source is omitted" do
      with_user_config_home do
        with_tmp_project do |root|
          skillfile = load_skillfile(root, 'skill "rails/conventions"')

          expect(skillfile.source).to eq("https://rubyskills.org")
        end
      end
    end

    it "uses an explicit source instead of the configured registry" do
      with_user_config_home do |directory|
        RubySkills::UserConfig.load(directory: directory).update_registry!(
          "https://configured.example"
        )
        with_tmp_project do |root|
          skillfile = load_skillfile(
            root,
            <<~RUBY
              source "https://staging.rubyskills.org"
              skill "rails/conventions"
            RUBY
          )

          expect(skillfile.source).to eq("https://staging.rubyskills.org")
        end
      end
    end

    it "raises when the Skillfile is missing" do
      with_tmp_project do |root|
        expect {
          described_class.load(root.join("Skillfile"))
        }.to raise_error(
          RubySkills::Skillfile::Error,
          a_string_including("Skillfile not found")
        )
      end
    end

    it "raises when the Skillfile is malformed Ruby" do
      with_tmp_project do |root|
        path = write_skillfile(root, "skill (")

        expect {
          described_class.load(path)
        }.to raise_error(RubySkills::Skillfile::Error, /Malformed Skillfile/)
      end
    end

    it "rejects malformed skill identifiers" do
      with_tmp_project do |root|
        expect {
          load_skillfile(root, 'skill "rails-conventions"')
        }.to raise_error(
          RubySkills::Skillfile::Error,
          a_string_including("Invalid skill identifier", "rails-conventions")
        )
      end
    end

    it "rejects invalid version requirements" do
      with_tmp_project do |root|
        expect {
          load_skillfile(root, 'skill "rails/conventions", "not-a-version"')
        }.to raise_error(
          RubySkills::Skillfile::Error,
          a_string_including("Invalid version requirement", "rails/conventions")
        )
      end
    end

    it "rejects duplicated skill declarations" do
      with_tmp_project do |root|
        expect {
          load_skillfile(
            root,
            <<~RUBY
              skill "rails/conventions", "~> 1.0"
              skill "rails/conventions", "~> 2.0"
            RUBY
          )
        }.to raise_error(
          RubySkills::Skillfile::Error,
          a_string_including("Duplicated skill", "rails/conventions")
        )
      end
    end

    it "rejects a second source declaration" do
      with_tmp_project do |root|
        expect {
          load_skillfile(
            root,
            <<~RUBY
              source "https://rubyskills.org"
              source "https://example.com"
              skill "rails/conventions"
            RUBY
          )
        }.to raise_error(
          RubySkills::Skillfile::Error,
          a_string_including("Duplicated source declaration")
        )
      end
    end

    it "rejects unknown DSL commands" do
      with_tmp_project do |root|
        expect {
          load_skillfile(root, 'plugin "rails/conventions"')
        }.to raise_error(
          RubySkills::Skillfile::Error,
          a_string_including("Unsupported Skillfile method `plugin`")
        )
      end
    end

    it "includes filename and line on DSL errors" do
      with_tmp_project do |root|
        path = write_skillfile(root, "skill \"rails/conventions\"\nplugin :nope\n")

        expect {
          described_class.load(path)
        }.to raise_error(
          an_instance_of(RubySkills::Skillfile::Error)
            .and(having_attributes(filename: path.to_s, line: 2))
        )
      end
    end
  end

  describe ".find_or_build" do
    it "returns the nearest Skillfile when one exists" do
      with_user_config_home do
        with_tmp_project do |root|
          write_skillfile(root, 'skill "rails/conventions"')
          nested = root.join("app")
          FileUtils.mkdir_p(nested)

          skillfile = described_class.find_or_build(nested)

          expect(skillfile.path).to eq(root.join("Skillfile"))
          expect(skillfile).to include("rails/conventions")
        end
      end
    end

    it "builds an in-memory Skillfile without writing" do
      with_user_config_home do
        with_tmp_project do |root|
          skillfile = described_class.find_or_build(root)

          expect(skillfile.path).to eq(root.join("Skillfile"))
          expect(skillfile.source).to eq("https://rubyskills.org")
          expect(skillfile.dependencies).to be_empty
          expect(root.join("Skillfile")).not_to exist
        end
      end
    end
  end

  describe ".pessimistic_requirement" do
    it "writes a two-segment pessimistic constraint by default" do
      with_tmp_project do |root|
        skillfile = load_skillfile(root, 'skill "rails/conventions", "~> 1.0"')

        expect(
          described_class.pessimistic_requirement("2.1.4", skillfile: skillfile)
        ).to eq("~> 2.1")
      end
    end

    it "follows patch-level pessimistic constraints already in the Skillfile" do
      with_tmp_project do |root|
        skillfile = load_skillfile(root, 'skill "rails/conventions", "~> 1.3.2"')

        expect(
          described_class.pessimistic_requirement("2.1.4", skillfile: skillfile)
        ).to eq("~> 2.1.4")
      end
    end
  end

  describe ".find" do
    it "walks parent directories until it finds a Skillfile" do
      with_user_config_home do
        with_tmp_project do |root|
          write_skillfile(root, 'skill "rails/conventions"')
          nested = root.join("app", "models")
          FileUtils.mkdir_p(nested)

          skillfile = described_class.find(nested)

          expect(skillfile.path).to eq(root.join("Skillfile"))
          expect(skillfile).to include("rails/conventions")
        end
      end
    end

    it "raises when no Skillfile exists before the filesystem root" do
      with_tmp_project do |root|
        nested = root.join("lib")
        FileUtils.mkdir_p(nested)

        expect {
          described_class.find(nested)
        }.to raise_error(
          RubySkills::Skillfile::Error,
          a_string_including("Skillfile not found")
        )
      end
    end
  end

  describe "#add" do
    it "appends a skill line without rewriting existing declarations" do
      with_tmp_project do |root|
        path = write_skillfile(
          root,
          <<~RUBY
            source "https://rubyskills.org"

            skill "rails/conventions", "~> 1.0"
          RUBY
        )
        skillfile = described_class.load(path)
        skillfile.add("rails/request-specs")
        skillfile.append_skill("rails/request-specs")

        reloaded = described_class.load(path)
        expect(path.read).to include('skill "rails/conventions", "~> 1.0"')
        expect(path.read).to include('skill "rails/request-specs"')
        expect(reloaded).to include("rails/request-specs")
        expect(reloaded.find("rails/request-specs").requirement).to eq(
          Gem::Requirement.default
        )
      end
    end
  end

  describe "#replace_requirement" do
    it "updates the requirement in memory without writing" do
      with_tmp_project do |root|
        path = write_skillfile(root, 'skill "rails/request-specs", "~> 2.1"')
        original = path.read
        skillfile = described_class.load(path)
        skillfile.replace_requirement("rails/request-specs", "= 2.1.4")

        expect(skillfile.find("rails/request-specs").requirement).to eq(
          Gem::Requirement.new("= 2.1.4")
        )
        expect(path.read).to eq(original)
      end
    end

    it "raises when the skill is not declared" do
      with_tmp_project do |root|
        skillfile = load_skillfile(root, 'skill "rails/conventions"')

        expect {
          skillfile.replace_requirement("rails/request-specs", "~> 2.0")
        }.to raise_error(
          RubySkills::Skillfile::Error,
          a_string_including("rails/request-specs is not declared in Skillfile")
        )
      end
    end
  end

  describe "#remove" do
    it "drops the declaration in memory without writing" do
      with_tmp_project do |root|
        path = write_skillfile(
          root,
          <<~RUBY
            source "https://rubyskills.org"

            skill "rails/conventions", "~> 1.0"
            skill "rails/request-specs", "~> 2.1"
          RUBY
        )
        original = path.read
        skillfile = described_class.load(path)
        skillfile.remove("rails/request-specs")

        expect(skillfile).not_to include("rails/request-specs")
        expect(skillfile).to include("rails/conventions")
        expect(path.read).to eq(original)
      end
    end

    it "raises when the skill is not declared" do
      with_tmp_project do |root|
        skillfile = load_skillfile(root, 'skill "rails/conventions"')

        expect {
          skillfile.remove("rails/request-specs")
        }.to raise_error(
          RubySkills::Skillfile::Error,
          a_string_including("rails/request-specs is not declared in Skillfile")
        )
      end
    end
  end

  describe "#write" do
    it "rewrites remaining skills in original order with a trailing newline" do
      with_tmp_project do |root|
        path = write_skillfile(
          root,
          <<~RUBY
            source "https://rubyskills.org"

            skill "rails/conventions", "~> 1.0"
            skill "rails/request-specs", "~> 2.1"
            skill "ruby/gem-development"
          RUBY
        )
        skillfile = described_class.load(path)
        skillfile.remove("rails/request-specs")
        skillfile.write

        expect(path.read).to eq(<<~RUBY)
          source "https://rubyskills.org"

          skill "rails/conventions", "~> 1.0"
          skill "ruby/gem-development"
        RUBY
        expect(path.read).to end_with("\n")
      end
    end

    it "is byte-identical for the same remaining dependencies" do
      with_tmp_project do |root|
        path = write_skillfile(
          root,
          <<~RUBY
            source "https://rubyskills.org"

            skill "rails/conventions", "~> 1.0"
            skill "rails/request-specs", "~> 2.1"
          RUBY
        )
        first = described_class.load(path)
        first.remove("rails/request-specs")
        first.write
        snapshot = path.read

        second = described_class.load(path)
        second.write

        expect(path.read).to eq(snapshot)
      end
    end
  end
end
