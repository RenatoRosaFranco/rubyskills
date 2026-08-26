# frozen_string_literal: true

require "json"

module RubySkills
  # Reports newer registry versions for Skillfile dependencies.
  #
  # Reads Skillfile, Skills.lock, and the registry. Does not install, update,
  # or rewrite any project files.
  #
  # @example
  #   result = RubySkills::Outdated.new.run
  #   result.exit_status # => 0, 1
  #
  # @since 0.1.0
  class Outdated # rubocop:disable Metrics/ClassLength
    STATUSES = {
      current: "current",
      update_available: "update available",
      constrained: "constrained",
      missing: "missing",
      locked_version_unavailable: "locked version unavailable"
    }.freeze

    Row = Struct.new(:name, :current, :allowed, :latest, :status, keyword_init: true) do
      # @return [Hash]
      def as_json
        {
          "name" => name,
          "current" => current&.to_s,
          "allowed" => allowed&.to_s,
          "latest" => latest&.to_s,
          "status" => status.to_s
        }
      end

      # @return [String]
      def human_status
        STATUSES.fetch(status)
      end

      # @return [String]
      def current_label
        current&.to_s || "-"
      end

      # @return [String]
      def allowed_label
        allowed&.to_s || "-"
      end

      # @return [String]
      def latest_label
        latest&.to_s || "-"
      end
    end

    Result = Struct.new(:rows, keyword_init: true) do
      # @return [Integer] +0+ when every row is current, otherwise +1+
      def exit_status
        rows.all? { |row| row.status == :current } ? 0 : 1
      end

      # @return [Array<Hash>]
      def as_json
        rows.map(&:as_json)
      end
    end

    # @param name [String, nil] limit the report to one Skillfile dependency
    # @param client [Registry::Client]
    # @param starting_directory [String, Pathname]
    def initialize(name: nil, client: nil, starting_directory: Dir.pwd)
      @name = name.to_s.strip.empty? ? nil : name.to_s.strip
      @client = client || Registry::Client.new
      @starting_directory = starting_directory
      @catalog = {}
    end

    # @return [Result]
    # @raise [RubySkills::Error]
    def run
      skillfile = Skillfile.find(@starting_directory)
      ensure_declared!(skillfile)
      lockfile = load_lockfile(skillfile)

      Result.new(rows: dependencies_for(skillfile).map { |dependency|
        row_for(dependency, lockfile)
      })
    end

    private

    # @param skillfile [Skillfile]
    # @return [void]
    def ensure_declared!(skillfile)
      return if @name.nil?
      return if skillfile.include?(@name)

      raise RubySkills::Error, "Skill `#{@name}` is not in the Skillfile"
    end

    # @param skillfile [Skillfile]
    # @return [Array<Dependency>]
    def dependencies_for(skillfile)
      deps = skillfile.dependencies.sort_by(&:name)
      return deps if @name.nil?

      deps.select { |dependency| dependency.name == @name }
    end

    # @param skillfile [Skillfile]
    # @return [Lockfile, nil]
    def load_lockfile(skillfile)
      path = Config.new(root: skillfile.path.dirname).lockfile_path
      return unless path.file?

      Lockfile.load(path)
    end

    # @param dependency [Dependency]
    # @param lockfile [Lockfile, nil]
    # @return [Row]
    def row_for(dependency, lockfile)
      current = lockfile&.find(dependency.name)&.version
      skill = catalog_skill(dependency.name)
      unless skill
        return Row.new(
          name: dependency.name,
          current: current,
          allowed: nil,
          latest: nil,
          status: :missing
        )
      end

      versions = published_versions(skill)
      latest = versions.max
      allowed = versions.select { |version|
        dependency.requirement.satisfied_by?(version)
      }.max

      Row.new(
        name: dependency.name,
        current: current,
        allowed: allowed,
        latest: latest,
        status: status_for(current: current, allowed: allowed, latest: latest, versions: versions)
      )
    end

    # @param current [Gem::Version, nil]
    # @param allowed [Gem::Version, nil]
    # @param latest [Gem::Version, nil]
    # @param versions [Array<Gem::Version>]
    # @return [Symbol]
    def status_for(current:, allowed:, latest:, versions:)
      return :missing if current.nil? || latest.nil?
      return :locked_version_unavailable unless versions.include?(current)

      progress_status(current, allowed, latest)
    end

    # @param current [Gem::Version]
    # @param allowed [Gem::Version, nil]
    # @param latest [Gem::Version]
    # @return [Symbol]
    def progress_status(current, allowed, latest)
      return :update_available if allowed && allowed > current
      return :constrained if allowed.nil? || latest > allowed

      :current
    end

    # @param name [String]
    # @return [Registry::Skill, nil]
    def catalog_skill(name)
      return @catalog[name] if @catalog.key?(name)

      @catalog[name] = @client.get_skill(name)
    rescue Registry::Error => e
      raise unless not_found?(e)

      @catalog[name] = nil
    end

    # @param error [Registry::Error]
    # @return [Boolean]
    def not_found?(error)
      error.code == "not_found" || error.status == 404
    end

    # @param skill [Registry::Skill]
    # @return [Array<Gem::Version>]
    def published_versions(skill)
      Array(skill.versions).filter_map { |value|
        next unless Gem::Version.correct?(value)

        Gem::Version.new(value)
      }.uniq
    end
  end
end
