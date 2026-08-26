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

    desc "install SKILL", "Install a skill from the registry"
    # Download +SKILL+ from the registry into +.ruby-skills+.
    #
    # Does not read a Skillfile or sync editor adapters.
    #
    # @param name [String] +namespace/name+
    # @return [void]
    # @raise [SystemExit] when the skill cannot be installed
    def install(name = nil)
      if name.to_s.strip.empty?
        say "Error: skill name is required (namespace/name)", :red
        exit 1
      end

      result = Install.new(name).run
      print_install(result)
      exit 1 unless result.success?
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

    desc "info SKILL", "Show registry metadata for a skill"
    # Look up +SKILL+ on the registry without installing it.
    #
    # @param name [String] +namespace/name+
    # @return [void]
    # @raise [SystemExit] when the skill cannot be found
    def info(name)
      result = Info.new(name).run
      print_info(result)
      exit 1 unless result.success?
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "publish [PATH]", "Publish a local Ruby Skill to the registry"
    # Validate, package, and upload +PATH+ as an immutable registry version.
    #
    # @param path [String] skill directory (defaults to +.+ )
    # @return [void]
    # @raise [SystemExit] when validation or upload fails
    def publish(path = ".")
      result = Publish.new(path).run
      print_publish(result)
      exit 1 unless result.success?
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "config [KEY] [VALUE]", "Get or set user configuration"
    # Show or persist user settings from +~/.config/ruby-skills/config.yml+.
    #
    # With no arguments, print the current file. With +registry+, show or set
    # the registry origin (production, staging, or localhost).
    #
    # @param key [String, nil]
    # @param value [String, nil]
    # @return [void]
    # @raise [SystemExit] when the key or value is invalid
    def config(key = nil, value = nil)
      case key
      when nil
        say "registry: #{UserConfig.load.registry}"
      when "registry"
        configure_registry(value)
      else
        say "Error: unknown config key: #{key}", :red
        exit 1
      end
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "login", "Save a registry API token"
    option :token, type: :string,
                   desc: "API token issued by the registry (rsk_...)"
    # Store a registry token in +~/.config/ruby-skills/credentials.yml+.
    #
    # Device authorization (browser code) is not implemented yet; pass
    # +--token+ for this cycle.
    #
    # @return [void]
    # @raise [SystemExit] when +--token+ is missing or invalid
    def login
      token = options[:token]
      unless token.is_a?(String) && !token.strip.empty?
        print_login_help
        exit 1
      end

      Credentials.load.update_token!(token)
      say "Logged in."
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "logout", "Remove the saved registry API token"
    # Delete the token from +credentials.yml+.
    #
    # @return [void]
    def logout
      Credentials.load.clear!
      say "Logged out."
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
      # @param result [RubySkills::Publish::Result]
      # @return [void]
      def print_publish(result)
        say "Publishing #{result.label}"
        say ""

        case result.status
        when :published
          print_publish_success(result)
        when :conflict
          print_publish_conflict(result)
        when :unauthenticated
          print_publish_login
        when :invalid
          result.failures.each do |failure|
            say "✗ #{failure}"
          end
          say ""
          say "Skill is invalid."
        else
          say "✗ #{result.error}"
        end
      end

      # @api private
      # @param result [RubySkills::Publish::Result]
      # @return [void]
      def print_publish_success(result)
        say "✓ manifest validated"
        say "✓ artifact built"
        say "✓ checksum verified"
        say "✓ uploaded"
        say "✓ published"
        say ""
        say "#{result.published.name} #{result.published.version} published successfully"
        say ""
        say result.published.url
      end

      # @api private
      # @param result [RubySkills::Publish::Result]
      # @return [void]
      def print_publish_conflict(result)
        say "✗ #{result.label} already exists."
        say ""
        say "Published versions are immutable."
        say ""
        say "Increment the version in skill.yml and try again."
      end

      # @api private
      # @return [void]
      def print_publish_login
        say "✗ not logged in."
        say ""
        say "Run:"
        say ""
        say "  ruby-skills login --token rsk_..."
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
      # @param result [RubySkills::Info::Result]
      # @return [void]
      def print_info(result)
        unless result.success?
          say "Error: #{result.error.message}", :red
          return
        end

        print_info_success(result.skill)
      end

      # @api private
      # @param skill [RubySkills::Registry::Skill]
      # @return [void]
      def print_info_success(skill)
        say skill.name
        say ""
        say skill.summary.to_s
        say ""
        say "Latest"
        say skill.latest_version if skill.latest_version
        say ""
        say "Categories"
        skill.categories.each do |category|
          say category.name
        end
        say ""
        say "Versions"
        skill.versions.each do |version|
          say version
        end
        say ""
        say "Downloads"
        say format_count(skill.downloads)
        say ""
        say "Install"
        say "ruby-skills install #{skill.name}"
      end

      # @api private
      # @param result [RubySkills::Install::Result]
      # @return [void]
      def print_install(result)
        unless result.success?
          say "Error: #{result.error.message}", :red
          return
        end

        print_install_success(result)
      end

      # @api private
      # @param result [RubySkills::Install::Result]
      # @return [void]
      def print_install_success(result)
        say "Resolving #{result.name}..."
        say ""
        say "Found #{result.version}"
        say ""
        say "Downloading..."
        say "✓ checksum verified"
        say "✓ artifact valid"
        say "✓ installed"
        say ""
        say "#{result.name} #{result.version} installed"
      end

      # @api private
      # @param number [Integer]
      # @return [String]
      def format_count(number)
        number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
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
      # @param value [String, nil]
      # @return [void]
      def configure_registry(value)
        settings = UserConfig.load
        settings.update_registry!(value) if value

        say "registry: #{settings.registry}"
      end

      # @api private
      # @return [void]
      def print_login_help
        say "Browser sign-in is not available yet."
        say ""
        say "Create a token on the registry and run:"
        say ""
        say "  ruby-skills login --token rsk_..."
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
