# frozen_string_literal: true

require "set"

module RubySkills
  # Decides which locked and installed skills are still required after a
  # Skillfile dependency is removed.
  #
  # Walking {ResolvedSkill#dependencies} keeps every skill still reachable
  # from the remaining Skillfile. Unreachable transitives are removable.
  #
  # @since 0.1.0
  class RemovalPlanner
    Plan = Struct.new(:required_names, :obsolete_locked, :artifacts, keyword_init: true)
    Artifact = Struct.new(:name, :version, keyword_init: true)

    # @param removed_name [String]
    # @param skillfile [Skillfile] remaining declared intent
    # @param lockfile [Lockfile, nil]
    # @param resolution [Resolution]
    # @param config [Config]
    def initialize(removed_name:, skillfile:, lockfile:, resolution:, config:)
      @removed_name = removed_name
      @skillfile = skillfile
      @lockfile = lockfile
      @resolution = resolution
      @config = config
    end

    # @return [Plan]
    def plan
      required = required_names
      Plan.new(
        required_names: required,
        obsolete_locked: obsolete_locked(required),
        artifacts: removable_artifacts(required)
      )
    end

    private

    # Names that must stay installed after this removal.
    #
    # @return [Set<String>]
    def required_names
      names = Set.new
      @resolution.skills.each do |skill|
        collect_required(skill, names)
      end
      names.merge(@skillfile.dependencies.map(&:name))
    end

    # @param skill [ResolvedSkill]
    # @param names [Set<String>]
    # @return [void]
    def collect_required(skill, names)
      return unless names.add?(skill.name)

      Array(skill.dependencies).each do |dependency|
        nested_name = dependency.respond_to?(:name) ? dependency.name : dependency.to_s
        nested = @resolution.find(nested_name)
        if nested
          collect_required(nested, names)
        else
          names << nested_name
        end
      end
    end

    # @param required [Set<String>]
    # @return [Array<LockedSkill>]
    def obsolete_locked(required)
      Array(@lockfile&.skills).reject { |skill| required.include?(skill.name) }
    end

    # Only the explicitly removed skill and locked names that dropped out of
    # the resolved graph. Installed skills that were never locked are left
    # alone — absence from the Skillfile is not enough to delete them.
    #
    # @param required [Set<String>]
    # @return [Array<Artifact>]
    def removable_artifacts(required)
      candidates = Set.new
      candidates << @removed_name
      obsolete_locked(required).each do |skill|
        candidates << skill.name
      end

      candidates.flat_map { |name|
        next [] if required.include?(name)

        Install.installed_versions(name, config: @config).map { |version|
          Artifact.new(name: name, version: version)
        }
      }
    end
  end
end
