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

    desc "install [SKILL]", "Install Skillfile dependencies or a registry skill"
    option :save, type: :boolean, default: false,
                  desc: "Add SKILL to Skillfile and refresh Skills.lock"
    option :version, type: :string,
                     desc: "Version requirement to write in Skillfile (requires --save)"
    # Install every Skillfile dependency, or one registry skill.
    #
    # With no +SKILL+, find the nearest Skillfile, resolve against Skills.lock,
    # and install missing artifacts. With +SKILL+, install that skill from the
    # registry. +--save+ persists +SKILL+ in the Skillfile after a successful
    # install. +--version+ writes that requirement; +SKILL@2.1.4+ writes += 2.1.4+.
    #
    # @param name [String, nil] +namespace/name+, or +nil+ for a project install
    # @return [void]
    # @raise [SystemExit] when the skill cannot be installed
    def install(name = nil)
      identifier = name.to_s.strip
      version = options[:version]
      require_save_for_version!(version)
      require_name_for_save!(identifier)
      dispatch_install(identifier, version)
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
      skills = LegacyLockfile.new.skills

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
    option :save, type: :boolean, default: false,
                  desc: "Remove SKILL from Skillfile and Skills.lock"
    # Remove an installed skill, or drop it from the project Skillfile.
    #
    # Without +--save+, only canonical +.ruby-skills+ storage is changed.
    # With +--save+, the declaration is removed from Skillfile, remaining
    # dependencies are re-resolved, and Skills.lock is rewritten.
    #
    # @param skill [String] +namespace/name+
    # @return [void]
    # @raise [SystemExit] when removal fails
    def remove(skill)
      if options[:save]
        ProjectRemove.new(name: skill).run
      else
        Remover.new.remove(skill)
      end
    rescue ProjectRemove::NotDeclared => e
      say e.message
      exit 1
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "update [SKILL]", "Update Skillfile dependencies to the newest compatible versions"
    # Re-resolve Skillfile dependencies against the registry.
    #
    # With no +SKILL+, every declared skill is updated to the newest version
    # allowed by its requirement. With +SKILL+, only that dependency moves;
    # every other lock pin is kept.
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

    desc "outdated [SKILL]", "Show available updates for Skillfile dependencies"
    option :json, type: :boolean, default: false, aliases: "-j",
                  desc: "Output outdated status as JSON"
    # Compare Skills.lock pins to the newest registry versions.
    #
    # Does not rewrite Skillfile, Skills.lock, or installed artifacts.
    # Exit +0+ when every listed skill is current, +1+ when any row is not,
    # and +2+ when the project or registry cannot be read.
    #
    # @param name [String, nil] +namespace/name+, or +nil+ for every Skillfile skill
    # @return [void]
    # @raise [SystemExit]
    def outdated(name = nil)
      result = Outdated.new(name: name).run
      print_outdated(result)
      exit result.exit_status unless result.exit_status.zero?
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 2
    end

    desc "sync", "Expose installed skills to supported coding agents"
    option :agent, type: :string,
                   desc: "Sync only this agent (claude, codex, cursor, vscode)"
    option :dry_run, type: :boolean, default: false,
                     desc: "Show pending adapter changes without writing"
    # Mirror locked skills into detected agent directories.
    #
    # Canonical +.ruby-skills+ storage is not modified. Missing agents are
    # reported as not detected. +--agent+ limits the run to one adapter.
    # +--dry-run+ prints pending adds and removes without writing.
    #
    # @return [void]
    # @raise [SystemExit] when the project cannot be synchronized
    def sync
      Sync.new(agent: options[:agent], dry_run: options[:dry_run]).run
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

    desc "login", "Log in to the registry via browser"
    option :token, type: :string,
                   desc: "API token issued by the registry (rsk_...), skips the browser"
    # Store a registry token in +~/.config/ruby-skills/credentials.yml+.
    #
    # With no options, start a device login: print a URL, open the browser,
    # and poll until the grant is approved. Pass +--token+ to paste a token.
    #
    # @return [void]
    # @raise [SystemExit] when login fails
    def login
      token = options[:token]
      if token == true || (token.is_a?(String) && token.strip.empty?)
        print_login_help
        exit 1
      end

      result = Login.new(token: token.is_a?(String) ? token : nil)
                    .run { |session| print_device_login(session) }
      print_login_result(result)
      exit 1 unless result.success?
    rescue RubySkills::Error => e
      say "Error: #{e.message}", :red
      exit 1
    end

    desc "logout", "Remove the saved registry API token"
    # Delete the token from +credentials.yml+.
    #
    # @return [void]
    def logout
      credentials = Credentials.load
      if credentials.token.nil?
        say "Not logged in."
        return
      end

      credentials.clear!
      say "Logged out."
    end

    desc "whoami", "Show the logged-in registry user"
    option :json, type: :boolean, default: false, aliases: "-j",
                  desc: "Output username and email as JSON"
    # Print the current registry user's username and email.
    #
    # @return [void]
    # @raise [SystemExit] when no token is stored or the registry rejects it
    def whoami
      result = Whoami.new.run
      print_whoami(result)
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
      # @param version [String, nil]
      # @return [void]
      def require_save_for_version!(version)
        return unless version
        return if options[:save]

        say "Error: --version requires --save", :red
        exit 1
      end

      # @api private
      # @param identifier [String]
      # @return [void]
      def require_name_for_save!(identifier)
        return unless options[:save]
        return unless identifier.empty?

        say "Error: --save requires a skill name (namespace/name)", :red
        exit 1
      end

      # @api private
      # @param identifier [String]
      # @param version [String, nil]
      # @return [void]
      def dispatch_install(identifier, version)
        if identifier.empty?
          run_project_install
        elsif options[:save]
          run_project_install(save: identifier, version: version)
        else
          run_direct_install(identifier)
        end
      end

      # @api private
      # @param save [String, nil]
      # @param version [String, nil]
      # @return [void]
      def run_project_install(save: nil, version: nil)
        ProjectInstall.new(save: save, version: version).run
      end

      # @api private
      # @param name [String]
      # @return [void]
      def run_direct_install(name)
        result = Install.new(name).run
        print_install(result)
        exit 1 unless result.success?
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
        say "  ruby-skills login"
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
        say "Pass a token with --token, or run ruby-skills login to open a browser."
        say ""
        say "  ruby-skills login"
        say "  ruby-skills login --token rsk_..."
      end

      # @api private
      # @param session [RubySkills::Registry::DeviceLogin]
      # @return [void]
      def print_device_login(session)
        say "Opening a browser to authenticate."
        say ""
        say "If the browser does not open, visit:"
        say ""
        say "  #{session.verification_uri}"
        say ""
        say "Waiting for confirmation..."
      end

      # @api private
      # @param result [RubySkills::Login::Result]
      # @return [void]
      def print_login_result(result)
        if result.success?
          say "Logged in."
          return
        end

        say "Error: #{result.error.message}", :red
      end

      # @api private
      # @param result [RubySkills::Outdated::Result]
      # @return [void]
      def print_outdated(result)
        if options[:json]
          puts JSON.generate(result.as_json)
          return
        end

        say Outdated::Report.new(result).to_s.chomp
      end

      # @api private
      # @param result [RubySkills::Whoami::Result]
      # @return [void]
      def print_whoami(result)
        unless result.success?
          if result.status == :unauthenticated
            say "Not logged in."
            say ""
            say "Run:"
            say ""
            say "  ruby-skills login"
            return
          end

          say "Error: #{result.error.message}", :red
          return
        end

        if options[:json]
          puts JSON.generate(
            "username" => result.user.username,
            "email" => result.user.email
          )
          return
        end

        say "username: #{result.user.username}"
        say "email:    #{result.user.email}"
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
