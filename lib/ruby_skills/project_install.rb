# frozen_string_literal: true

module RubySkills
  # Installs every skill declared in the nearest {Skillfile}.
  #
  # Resolves first, downloads and verifies every missing artifact, then
  # extracts and writes +Skills.lock+ atomically. Locked versions are kept
  # when they still satisfy the Skillfile.
  #
  # +save+ appends a registry skill to the Skillfile after a successful
  # install. The Skillfile is not written if resolution or installation fails.
  #
  # @example
  #   RubySkills::ProjectInstall.new.run
  #
  # @example Persist a dependency
  #   RubySkills::ProjectInstall.new(save: "rails/request-specs").run
  #
  # @since 0.1.0
  class ProjectInstall # rubocop:disable Metrics/ClassLength
    Prepared = Struct.new(:skill, :bytes, keyword_init: true)

    # @param save [String, nil] skill to persist in the Skillfile
    # @param version [String, nil] explicit requirement for +save+
    # @param client [Registry::Client]
    # @param starting_directory [String, Pathname]
    # @param output [#puts]
    def initialize(
      save: nil, version: nil, client: nil,
      starting_directory: Dir.pwd, output: $stdout
    )
      @requested = parse_requested(save, version)
      @client = client || Registry::Client.new
      @starting_directory = starting_directory
      @report = Report.new(output)
      @dirty = false
    end

    # @return [Resolution]
    # @raise [RubySkills::Error]
    def run
      return run_save if @requested

      run_declared
    end

    private

    # @param save [String, nil]
    # @param version [String, nil]
    # @return [RequestedSkill, nil]
    def parse_requested(save, version)
      identifier = save.to_s.strip
      return if identifier.empty?

      RequestedSkill.parse(identifier, version: version)
    end

    # @return [Resolution]
    def run_declared
      @report.reading
      skillfile = Skillfile.find(@starting_directory)
      config = Config.new(root: skillfile.path.dirname)
      lockfile = load_lockfile(config)

      @report.resolving
      resolution = resolve(skillfile, lockfile)
      return finish_current(resolution) if current?(resolution, lockfile, config)

      commit(prepare(resolution, config), resolution, skillfile, config)
      resolution
    end

    # @return [Resolution]
    def run_save
      skillfile = Skillfile.find_or_build(@starting_directory)
      existing = skillfile.find(@requested.name)

      return finish_already_declared(skillfile, existing) if skip_declaration?(existing)

      @report.adding(@requested.name)
      apply_declaration!(skillfile, existing)
      complete_save(skillfile)
    end

    # @param existing [Dependency, nil]
    # @return [Boolean]
    def skip_declaration?(existing)
      return false unless existing
      return true unless @requested.explicit?

      existing.requirement == parsed_requirement(@requested.requirement_string)
    end

    # @param skillfile [Skillfile]
    # @param existing [Dependency]
    # @return [Resolution]
    def finish_already_declared(skillfile, existing)
      @report.already_declared(existing)
      config = Config.new(root: skillfile.path.dirname)
      lockfile = load_lockfile(config)
      resolution = resolve(skillfile, lockfile)
      return resolution if current?(resolution, lockfile, config)

      commit_refresh(prepare(resolution, config), resolution, config)
      resolution
    end

    # @param skillfile [Skillfile]
    # @param existing [Dependency, nil]
    # @return [void]
    def apply_declaration!(skillfile, existing)
      @dirty = true
      if existing
        skillfile.replace_requirement(@requested.name, @requested.requirement_string)
        return
      end

      skillfile.add(@requested.name, @requested.requirement_string || ">= 0")
    end

    # @param skillfile [Skillfile]
    # @return [Resolution]
    def complete_save(skillfile)
      config = Config.new(root: skillfile.path.dirname)
      lockfile = load_lockfile(config)
      @report.resolving_dependencies
      resolution = resolve(skillfile, lockfile)
      resolution = apply_pessimistic(skillfile, resolution) unless @requested.explicit?
      commit_save(prepare(resolution, config), resolution, skillfile, config)
      resolution
    end

    # @param skillfile [Skillfile]
    # @param resolution [Resolution]
    # @return [Resolution]
    def apply_pessimistic(skillfile, resolution)
      resolved = resolution.find(@requested.name)
      return resolution unless resolved

      requirement = Skillfile.pessimistic_requirement(resolved.version, skillfile: skillfile)
      skillfile.replace_requirement(@requested.name, requirement)
      Resolution.new(
        source: resolution.source,
        skills: resolution.skills.to_a,
        dependencies: skillfile.dependencies
      )
    end

    # @param skillfile [Skillfile]
    # @param lockfile [Lockfile, nil]
    # @return [Resolution]
    def resolve(skillfile, lockfile)
      Resolver.new(skillfile: skillfile, lockfile: lockfile, client: @client).resolve
    end

    # @param config [Config]
    # @return [Lockfile, nil]
    def load_lockfile(config)
      return unless config.lockfile_path.file?

      Lockfile.load(config.lockfile_path)
    end

    # @param resolution [Resolution]
    # @param lockfile [Lockfile, nil]
    # @param config [Config]
    # @return [Boolean]
    def current?(resolution, lockfile, config)
      return false if lockfile.nil?
      return false unless lock_matches?(resolution, lockfile)

      resolution.skills.all? { |skill|
        Install.installed?(skill.name, skill.version, config: config)
      }
    end

    # @param resolution [Resolution]
    # @param lockfile [Lockfile]
    # @return [Boolean]
    def lock_matches?(resolution, lockfile)
      return false if resolution.skills.size != lockfile.skills.size

      resolution.skills.all? { |skill|
        locked = lockfile.find(skill.name)
        locked && locked.version == skill.version && locked.checksum == skill.checksum
      }
    end

    # @param resolution [Resolution]
    # @return [Resolution]
    def finish_current(resolution)
      @report.up_to_date
      resolution
    end

    # @param resolution [Resolution]
    # @param config [Config]
    # @return [Array<Prepared>]
    def prepare(resolution, config)
      resolution.skills.filter_map { |skill|
        if Install.installed?(skill.name, skill.version, config: config)
          @report.using(skill) unless @requested
          next
        end

        @report.fetching(skill)
        Prepared.new(skill: skill, bytes: download_verified(skill))
      }
    end

    # @param skill [ResolvedSkill]
    # @return [String]
    def download_verified(skill)
      download = @client.download(skill.name, skill.version.to_s)
      Install.verify_checksum!(download.checksum, skill.checksum)
      download.bytes
    end

    # @param prepared [Array<Prepared>]
    # @param resolution [Resolution]
    # @param skillfile [Skillfile]
    # @param config [Config]
    # @return [void]
    def commit(prepared, resolution, _skillfile, config)
      extract_all(prepared, config)
      @report.writing_lock
      resolution.to_lockfile.write(config.lockfile_path)
      @report.installed(resolution.skills.size)
    end

    # @param prepared [Array<Prepared>]
    # @param resolution [Resolution]
    # @param skillfile [Skillfile]
    # @param config [Config]
    # @return [void]
    def commit_save(prepared, resolution, skillfile, config)
      extract_all(prepared, config)
      @report.checksums_verified if prepared.any?
      @report.installed_ok
      persist_skillfile(skillfile)
      resolution.to_lockfile.write(config.lockfile_path)
      @report.lock_updated
      @report.added(@requested.name, skillfile.find(@requested.name).requirement)
    end

    # @param prepared [Array<Prepared>]
    # @param resolution [Resolution]
    # @param config [Config]
    # @return [void]
    def commit_refresh(prepared, resolution, config)
      extract_all(prepared, config)
      @report.checksums_verified if prepared.any?
      @report.installed_ok
      resolution.to_lockfile.write(config.lockfile_path)
      @report.lock_updated
    end

    # @param prepared [Array<Prepared>]
    # @param config [Config]
    # @return [void]
    def extract_all(prepared, config)
      prepared.each do |item|
        @report.installing(item.skill) unless @requested
        Install.extract(
          bytes: item.bytes,
          checksum: item.skill.checksum,
          destination: Install.destination(
            item.skill.name,
            item.skill.version,
            config: config
          )
        )
      end
    end

    # @param skillfile [Skillfile]
    # @return [void]
    def persist_skillfile(skillfile)
      return unless @dirty

      skillfile.write
      @report.skillfile_updated
    end

    # @param value [String]
    # @return [Gem::Requirement]
    def parsed_requirement(value)
      Gem::Requirement.new(value)
    end
  end
end
