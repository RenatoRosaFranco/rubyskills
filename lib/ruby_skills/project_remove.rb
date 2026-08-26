# frozen_string_literal: true

module RubySkills
  # Removes a declared skill from the nearest Skillfile and refreshes
  # Skills.lock and canonical storage.
  #
  # Validation and resolution run before any filesystem mutation. Skillfile
  # and Skills.lock are written atomically; installed artifacts are removed
  # after those writes succeed.
  #
  # @example
  #   RubySkills::ProjectRemove.new(name: "rails/request-specs").run
  #
  # @since 0.1.0
  class ProjectRemove # rubocop:disable Metrics/ClassLength
    # Raised when +--save+ names a skill that is not in the Skillfile.
    class NotDeclared < RubySkills::Error; end

    # @param name [String]
    # @param client [Registry::Client]
    # @param starting_directory [String, Pathname]
    # @param output [#puts]
    def initialize(name:, client: nil, starting_directory: Dir.pwd, output: $stdout)
      @name = name.to_s.strip
      @client = client || Registry::Client.new
      @starting_directory = starting_directory
      @report = Report.new(output)
    end

    # @return [Resolution]
    # @raise [RubySkills::Error]
    def run
      skillfile = Skillfile.find(@starting_directory)
      ensure_declared!(skillfile)
      @report.removing(@name)

      config = Config.new(root: skillfile.path.dirname)
      lockfile = load_lockfile(config)
      skillfile.remove(@name)
      resolution = resolve_remaining(skillfile, lockfile)
      plan = RemovalPlanner.new(
        removed_name: @name,
        skillfile: skillfile,
        lockfile: lockfile,
        resolution: resolution,
        config: config
      ).plan
      validate_plan!(plan, config)
      commit(skillfile, resolution, plan, config)
      resolution
    end

    private

    # @param skillfile [Skillfile]
    # @return [void]
    def ensure_declared!(skillfile)
      return if skillfile.include?(@name)

      raise NotDeclared, "#{@name} is not declared in Skillfile."
    end

    # @param config [Config]
    # @return [Lockfile, nil]
    def load_lockfile(config)
      return unless config.lockfile_path.file?

      Lockfile.load(config.lockfile_path)
    end

    # @param skillfile [Skillfile]
    # @param lockfile [Lockfile, nil]
    # @return [Resolution]
    def resolve_remaining(skillfile, lockfile)
      return Resolution.new(source: skillfile.source, skills: [], dependencies: []) if
        skillfile.dependencies.empty?

      Resolver.new(
        skillfile: skillfile,
        lockfile: lockfile,
        client: @client
      ).resolve
    end

    # @param plan [RemovalPlanner::Plan]
    # @param config [Config]
    # @return [void]
    def validate_plan!(plan, config)
      plan.artifacts.each do |artifact|
        Install.assert_removable!(artifact.name, artifact.version, config: config)
      end
    end

    # @param skillfile [Skillfile]
    # @param resolution [Resolution]
    # @param plan [RemovalPlanner::Plan]
    # @param config [Config]
    # @return [void]
    def commit(skillfile, resolution, plan, config)
      skillfile.write
      resolution.to_lockfile.write(config.lockfile_path)
      removed = remove_artifacts(plan, config)
      report_commit(plan, removed)
      sync_adapters(config)
    end

    # @param plan [RemovalPlanner::Plan]
    # @param config [Config]
    # @return [Array<RemovalPlanner::Artifact>]
    def remove_artifacts(plan, config)
      removed = []
      plan.artifacts.each do |artifact|
        Install.remove_version!(artifact.name, artifact.version, config: config)
        removed << artifact
      rescue StandardError => e
        raise RubySkills::Error, artifact_failure_message(removed, artifact, e)
      end
      removed
    end

    # @param removed [Array<RemovalPlanner::Artifact>]
    # @param artifact [RemovalPlanner::Artifact]
    # @param error [Exception]
    # @return [String]
    def artifact_failure_message(removed, artifact, error)
      parts = ["Skillfile and Skills.lock were updated."]
      if removed.any?
        names = removed.map { |item| "#{item.name} #{item.version}" }.join(", ")
        parts << "Removed #{names}."
      end
      parts << "Failed to remove #{artifact.name} #{artifact.version}: #{error.message}"
      parts.join(" ")
    end

    # @param plan [RemovalPlanner::Plan]
    # @param removed [Array<RemovalPlanner::Artifact>]
    # @return [void]
    def report_commit(plan, removed)
      @report.skillfile_updated
      report_artifacts(plan, removed)
      @report.lock_updated
      @report.done(@name)
    end

    # @param plan [RemovalPlanner::Plan]
    # @param removed [Array<RemovalPlanner::Artifact>]
    # @return [void]
    def report_artifacts(plan, removed)
      named = removed.select { |artifact| artifact.name == @name }
      report_named_artifacts(plan, named)
      removed.reject { |artifact| artifact.name == @name }.each do |artifact|
        @report.removed_artifact(artifact)
      end
    end

    # @param plan [RemovalPlanner::Plan]
    # @param named [Array<RemovalPlanner::Artifact>]
    # @return [void]
    def report_named_artifacts(plan, named)
      if named.any?
        named.each do |artifact|
          @report.removed_artifact(artifact)
        end
        return
      end

      return if plan.artifacts.any? { |artifact| artifact.name == @name }

      @report.no_artifact
    end

    # @param config [Config]
    # @return [void]
    def sync_adapters(config)
      Adapters.sync_remove(@name, root: config.root)
    rescue StandardError => e
      @report.adapter_failed(e)
    end
  end
end
