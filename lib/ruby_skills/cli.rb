# frozen_string_literal: true

require "thor"

module RubySkills
  # Thor-based command-line interface for Ruby Skills.
  #
  # The default command is {#help}. +-h+ and +--help+ are aliases for it.
  #
  # @example Initialize a project
  #   RubySkills::CLI.start(["init"])
  #
  # @since 0.1.0
  class CLI < Thor
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

    desc "init", "Initialize Ruby Skills in the current project"
    # Create a Skillfile and +.ruby-skills+ directory in the current project.
    #
    # @return [void]
    # @raise [SystemExit] when initialization fails
    def init
      config = Config.new

      config.initialize_project!

      say "Ruby Skills initialized"
      say " Skillfile created"
      say " .ruby-skills directory created"
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
    # Print installed skills from the lockfile.
    #
    # @return [void]
    def list
      lockfile = Lockfile.new

      if lockfile.skills.empty?
        say "No skills installed."
        return
      end

      say "Installed skills:"
      say ""

      lockfile.skills.each do |skill|
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

    desc "version", "Display Ruby Skills version"
    # Print the installed gem version.
    #
    # @return [void]
    def version
      say "ruby-skills #{RubySkills::VERSION}"
    end
  end
end
