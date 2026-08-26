# frozen_string_literal: true

module RubySkills
  # Exposes locked, installed skills to detected coding agents.
  #
  # Canonical +.ruby-skills+ storage is the source of truth. Adapters only
  # write disposable symlinks. Credentials and unrelated agent config are
  # never modified.
  #
  # @example
  #   RubySkills::Sync.new.run
  #
  # @example One agent, no writes
  #   RubySkills::Sync.new(agent: "claude", dry_run: true).run
  #
  # @since 0.1.0
  class Sync
    Result = Struct.new(:changes, :skill_count, :dry_run, keyword_init: true) do
      # @return [Integer]
      def agent_count
        changes.count(&:available)
      end
    end

    # @param agent [String, nil] adapter id, or +nil+ for every supported agent
    # @param dry_run [Boolean]
    # @param starting_directory [String, Pathname]
    # @param output [#puts]
    def initialize(agent: nil, dry_run: false, starting_directory: Dir.pwd, output: $stdout)
      @agent = agent.to_s.strip.empty? ? nil : agent.to_s.strip
      @dry_run = dry_run
      @starting_directory = starting_directory
      @report = Report.new(output)
    end

    # @return [Result]
    # @raise [RubySkills::Error]
    def run
      skillfile = Skillfile.find(@starting_directory)
      config = Config.new(root: skillfile.path.dirname)
      lockfile = load_lockfile(config)
      skills = installed_skills(lockfile, config)
      project = Adapters::Project.new(root: config.root, skills: skills)
      adapters = selected_adapters(config.root)
      changes = adapters.map { |adapter|
        adapter.sync(project: project, dry_run: @dry_run)
      }
      result = Result.new(changes: changes, skill_count: skills.size, dry_run: @dry_run)
      @report.print(result, adapters: adapters)
      result
    end

    private

    # @param config [Config]
    # @return [Lockfile]
    # @raise [RubySkills::Error]
    def load_lockfile(config)
      path = config.lockfile_path
      return Lockfile.load(path) if path.file?

      raise RubySkills::Error, "Skills.lock not found. Run ruby-skills install first."
    end

    # @param lockfile [Lockfile]
    # @param config [Config]
    # @return [Array<Adapters::Skill>]
    # @raise [RubySkills::Error]
    def installed_skills(lockfile, config)
      lockfile.skills.map { |locked|
        unless Install.installed?(locked.name, locked.version, config: config)
          raise RubySkills::Error,
                "#{locked.name} #{locked.version} is locked but not installed. " \
                "Run ruby-skills install."
        end

        Adapters::Skill.new(
          name: locked.name,
          version: locked.version,
          path: Install.destination(locked.name, locked.version, config: config)
        )
      }
    end

    # @param root [Pathname]
    # @return [Array<Adapters::Base>]
    # @raise [RubySkills::Error]
    def selected_adapters(root)
      klasses = adapter_classes
      klasses.map { |klass| klass.new(root: root) }
    end

    # @return [Array<Class>]
    # @raise [RubySkills::Error]
    def adapter_classes
      return Adapters.all if @agent.nil?

      klass = Adapters.find(@agent)
      return [klass] if klass

      raise RubySkills::Error,
            "Unknown agent #{@agent.inspect}. Supported: #{Adapters.ids.join(", ")}"
    end
  end
end
