# frozen_string_literal: true

module RubySkills
  # Re-resolves Skillfile dependencies to the newest versions allowed by each
  # requirement, then installs changed artifacts and rewrites Skills.lock.
  #
  # +install+ keeps a valid lock pin. +update+ asks the registry for the
  # newest compatible release. A named update re-resolves only that skill.
  #
  # @example Update every Skillfile dependency
  #   RubySkills::Updater.new.update
  #
  # @example Update one skill
  #   RubySkills::Updater.new.update("rails/conventions")
  #
  # @since 0.1.0
  class Updater
    Change = Struct.new(:skill, :from, :bytes, keyword_init: true)

    # @param client [Registry::Client]
    # @param starting_directory [String, Pathname]
    # @param output [#puts]
    def initialize(client: nil, starting_directory: Dir.pwd, output: $stdout)
      @client = client || Registry::Client.new
      @starting_directory = starting_directory
      @report = Report.new(output)
    end

    # @param skill_name [String, nil]
    # @return [Resolution]
    # @raise [RubySkills::Error]
    def update(skill_name = nil)
      @name = skill_name.to_s.strip.empty? ? nil : skill_name.to_s.strip
      skillfile = Skillfile.find(@starting_directory)
      ensure_declared!(skillfile)
      config = Config.new(root: skillfile.path.dirname)
      lockfile = load_lockfile(config)
      resolution = Resolver.new(
        skillfile: skillfile,
        lockfile: lockfile,
        client: @client,
        update: @name || true
      ).resolve

      changes = detect_changes(resolution, lockfile)
      return finish_current(resolution) if changes.empty?

      prepared = download_verified(changes)
      install_changes(prepared, config)
      report_unchanged(resolution, changes)
      resolution.to_lockfile.write(config.lockfile_path)
      @report.lock_updated
      resolution
    end

    private

    # @param skillfile [Skillfile]
    # @return [void]
    def ensure_declared!(skillfile)
      return if @name.nil?
      return if skillfile.include?(@name)

      raise RubySkills::Error, "Skill `#{@name}` is not in the Skillfile"
    end

    # @param config [Config]
    # @return [Lockfile, nil]
    def load_lockfile(config)
      return unless config.lockfile_path.file?

      Lockfile.load(config.lockfile_path)
    end

    # @param resolution [Resolution]
    # @param lockfile [Lockfile, nil]
    # @return [Array<Change>]
    def detect_changes(resolution, lockfile)
      resolution.skills.filter_map { |skill|
        next unless stale?(skill, lockfile)

        Change.new(skill: skill, from: lockfile&.find(skill.name)&.version)
      }
    end

    # @param skill [ResolvedSkill]
    # @param lockfile [Lockfile, nil]
    # @return [Boolean]
    def stale?(skill, lockfile)
      locked = lockfile&.find(skill.name)
      return true if locked.nil?

      locked.version != skill.version || locked.checksum != skill.checksum
    end

    # @param resolution [Resolution]
    # @return [Resolution]
    def finish_current(resolution)
      if @name
        @report.already_current(@name)
      else
        @report.all_current
      end
      resolution
    end

    # @param changes [Array<Change>]
    # @return [Array<Change>]
    def download_verified(changes)
      changes.each do |change|
        download = @client.download(change.skill.name, change.skill.version.to_s)
        Install.verify_checksum!(download.checksum, change.skill.checksum)
        change.bytes = download.bytes
      end
    end

    # @param prepared [Array<Change>]
    # @param config [Config]
    # @return [void]
    def install_changes(prepared, config)
      prepared.each do |change|
        @report.updating(change.skill.name)
        @report.bump(change.from || "uninstalled", change.skill.version)
        @report.downloaded
        @report.checksum_verified
        Install.extract(
          bytes: change.bytes,
          checksum: change.skill.checksum,
          destination: Install.destination(
            change.skill.name,
            change.skill.version,
            config: config
          )
        )
        @report.installed
      end
    end

    # @param resolution [Resolution]
    # @param changes [Array<Change>]
    # @return [void]
    def report_unchanged(resolution, changes)
      return if @name

      changed = changes.map { |change| change.skill.name }
      resolution.skills.each do |skill|
        next if changed.include?(skill.name)

        @report.already_current(skill.name)
      end
    end
  end
end
