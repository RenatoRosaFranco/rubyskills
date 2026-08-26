# frozen_string_literal: true

module RubySkills
  # Installs every skill declared in the nearest {Skillfile}.
  #
  # Resolves first, downloads and verifies every missing artifact, then
  # extracts and writes +Skills.lock+ atomically. Locked versions are kept
  # when they still satisfy the Skillfile.
  #
  # @example
  #   RubySkills::ProjectInstall.new.run
  #
  # @since 0.1.0
  class ProjectInstall
    Prepared = Struct.new(:skill, :bytes, keyword_init: true)

    # @param save [String, nil] skill to append to the Skillfile
    # @param client [Registry::Client]
    # @param starting_directory [String, Pathname]
    # @param output [#puts]
    def initialize(save: nil, client: nil, starting_directory: Dir.pwd, output: $stdout)
      @save = save.to_s.strip.empty? ? nil : save.to_s.strip
      @client = client || Registry::Client.new
      @starting_directory = starting_directory
      @report = Report.new(output)
      @appended = nil
    end

    # @return [Resolution]
    # @raise [RubySkills::Error]
    def run
      @report.reading
      skillfile = Skillfile.find(@starting_directory)
      remember_append(skillfile)
      config = Config.new(root: skillfile.path.dirname)
      lockfile = load_lockfile(config)

      @report.resolving
      resolution = Resolver.new(
        skillfile: skillfile,
        lockfile: lockfile,
        client: @client
      ).resolve

      return finish_current(resolution) if current?(resolution, lockfile, config)

      prepared = prepare(resolution, config)
      commit(prepared, resolution, skillfile, config)
      resolution
    end

    private

    # @param skillfile [Skillfile]
    # @return [void]
    def remember_append(skillfile)
      return if @save.nil? || skillfile.include?(@save)

      skillfile.add(@save)
      @appended = @save
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
          @report.using(skill)
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
    def commit(prepared, resolution, skillfile, config)
      prepared.each do |item|
        @report.installing(item.skill)
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

      skillfile.append_skill(@appended) if @appended
      @report.writing_lock
      resolution.to_lockfile.write(config.lockfile_path)
      @report.installed(resolution.skills.size)
    end
  end
end
