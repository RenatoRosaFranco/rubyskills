# frozen_string_literal: true

require "json"
require "thor"

module RubySkills
  # Thor-based command-line interface for Ruby Skills.
  #
  # The default command is {#help}. +-h+ and +--help+ are aliases for it.
  #
  # @example Create a skill
  #   RubySkills::CLI.start(["init", "rails/request-specs"])
  #
  # @since 0.1.0
  class CLI < Thor # rubocop:disable Metrics/ClassLength
    # Display name used in Thor help banners.
    package_name "ruby-skills"

    # Show {#help} when no command is given.
    default_command :help

    # Accept +-h+ and +--help+ as aliases for {#help}.
    map %w[-h --help] => :help

    desc "help [COMMAND]", "List all commands or show help for one command"
    # List every available command, or describe a single command.
    #
    # @param command [String, nil] command to describe, or +nil+ to list all
    # @param subcommand [Boolean] whether +command+ is a subcommand
    # @return [void]
    def help(command = nil, subcommand = false)
      super
    end

    desc "init [NAME]", "Create a new Ruby Skill or initialize an empty directory"
    # Scaffold a skill from +namespace/name+, or prompt when +NAME+ is omitted
    # inside an empty directory.
    #
    # @param name [String, nil] +namespace/name+, or +nil+ to prompt
    # @return [void]
    # @raise [SystemExit] when initialization fails
    def init(name = nil)
      result = if name
                 Generators::Skill.new.create(name)
               else
                 create_skill_interactively
               end

      print_created_skill(result)
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "install [Skill]", "Install one skill or all skills from Skillfile"
    # Install one skill or every skill declared in the Skillfile.
    #
    # @param skill [String, nil] skill name to install, or +nil+ to install all
    # @return [void]
    # @raise [SystemExit] when installation fails
    def install(skill = nil)
      Installer.new.install(skill)
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "list", "List installed skills"
    option :json, type: :boolean, default: false, aliases: "-j",
                  desc: "Output installed skills as JSON"
    # Print installed skills from the lockfile.
    #
    # With +--json+, emit a machine-readable payload instead of a table.
    #
    # @return [void]
    def list
      skills = Lockfile.new.skills

      if options[:json]
        puts JSON.generate(list_payload(skills))
        return
      end

      if skills.empty?
        say "No skills installed."
        return
      end

      say "Installed skills:"
      say ""

      skills.each do |name, data|
        say "#{name.ljust(35)} #{data["version"]}"
      end
    end

    desc "remove SKILL", "Remove an installed skill"
    # Remove an installed skill from the project.
    #
    # @param skill [String] name of the skill to remove
    # @return [void]
    # @raise [SystemExit] when removal fails
    def remove(skill)
      Remover.new.remove(skill)
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "update [SKILL]", "Update one skill or all installed skills"
    # Update one skill or every installed skill.
    #
    # @param skill [String, nil] skill name to update, or +nil+ to update all
    # @return [void]
    # @raise [SystemExit] when the update fails
    def update(skill = nil)
      Updater.new.update(skill)
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "validate [PATH]", "Validate a local Ruby Skill"
    # Validate the current directory or +PATH+ as a skill.
    #
    # @param path [String] skill directory (defaults to +.+ )
    # @return [void]
    # @raise [SystemExit] with status 1 when the skill is invalid
    def validate(path = ".")
      result = Validator.new(path).validate
      print_validation(result)
      exit 1 unless result.valid?
    end

    desc "build [PATH]", "Build a .rskill artifact from a local Ruby Skill"
    option :output, type: :string, default: "pkg", aliases: "-o",
                    desc: "Directory to write the artifact"
    # Validate +PATH+ and write a deterministic +.rskill+ archive.
    #
    # Default destination is +pkg/+. No archive is written when validation fails.
    #
    # @param path [String] skill directory (defaults to +.+ )
    # @return [void]
    # @raise [SystemExit] with status 1 when the skill is invalid
    def build(path = ".")
      result = Build.new(path, output: options[:output]).run
      print_build(result)
      exit 1 unless result.success?
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "version", "Display Ruby Skills version"
    # Print the installed gem version.
    #
    # @return [void]
    def version
      say "ruby-skills #{RubySkills::VERSION}"
    end

    no_commands do # rubocop:disable Metrics/BlockLength
      # @api private
      # @param skills [Hash{String => Hash}] lockfile skill map
      # @return [Hash] JSON-serializable list payload
      def list_payload(skills)
        {
          "skills" => skills.map do |name, data|
            {
              "name" => name,
              "version" => data["version"],
              "source" => data["source"]
            }
          end
        }
      end

      # @api private
      # @return [RubySkills::Generators::Skill::Result]
      # @raise [RubySkills::Error] if the current directory is not empty
      def create_skill_interactively
        unless empty_directory?(Dir.pwd)
          raise RubySkills::Error,
                "Current directory is not empty. Pass namespace/name, " \
                "e.g. ruby-skills init rails/request-specs"
        end

        namespace = ask("Namespace:").to_s.strip
        skill_name = ask("Name:").to_s.strip

        Generators::Skill.new.create("#{namespace}/#{skill_name}", in_place: true)
      end

      # @api private
      # @param path [String]
      # @return [Boolean]
      def empty_directory?(path)
        Pathname.new(path).children.empty?
      end

      # @api private
      # @param result [RubySkills::Generators::Skill::Result]
      # @return [void]
      def print_created_skill(result)
        folder = result.in_place ? "." : result.name

        say "Created Ruby Skill:"
        say ""
        say "  #{folder}/"
        say "  ├── skill.yml"
        say "  ├── SKILL.md"
        say "  └── references/"
        say ""
        say "Next:"
        say ""
        say "  cd #{result.name}" unless result.in_place
        say "  ruby-skills validate"
      end

      # @api private
      # @param result [RubySkills::Build::Result]
      # @return [void]
      def print_build(result)
        say "Building #{result.label}"
        say ""

        if result.success?
          print_build_success(result)
        else
          result.failures.each do |failure|
            say "✗ #{failure}"
          end
          say ""
          say "Skill is invalid."
        end
      end

      # @api private
      # @param result [RubySkills::Build::Result]
      # @return [void]
      def print_build_success(result)
        say "✓ manifest valid"
        say "✓ #{result.file_count} files included"
        say "✓ artifact created"
        say ""
        say result.output_path
        say ""
        say "SHA256:"
        say result.artifact.checksum
        say ""
        say "Size:"
        say format_size(result.artifact.size)
      end

      # @api private
      # @param bytes [Integer]
      # @return [String]
      def format_size(bytes)
        return "#{bytes} B" if bytes < 1024

        value = bytes.to_f / 1024
        return format("%.1f KB", value) if value < 1024

        format("%.1f MB", value / 1024)
      end

      # @api private
      # @param result [RubySkills::Validator::Result]
      # @return [void]
      def print_validation(result)
        say "Validating #{result.label}"
        say ""

        if result.valid?
          say "✓ manifest valid"
          say "✓ version valid"
          say "✓ entrypoint exists"
          say "✓ file paths are safe"
          say "✓ #{result.file_count} files included"
          say ""
          say "Skill is valid."
        else
          result.failures.each do |failure|
            say "✗ #{failure}"
          end
          say ""
          say "Skill is invalid."
        end
      end
    end
  end
end
