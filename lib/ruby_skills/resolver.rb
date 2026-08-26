# frozen_string_literal: true

require "rubygems"

module RubySkills
  # Resolves every {Skillfile} dependency to one published registry version.
  #
  # +install+ is not +update+. When a Skills.lock already pins a version that
  # still satisfies the Skillfile and is still available, that pin is kept.
  # A newer compatible release is chosen only when the pin is unusable or
  # when +update: true+.
  #
  # Yanked and unpublished releases are ignored. Versions are compared with
  # {Gem::Version}, never lexicographically. Nothing is downloaded or written.
  #
  # @example
  #   resolution = RubySkills::Resolver.new(
  #     skillfile: skillfile,
  #     lockfile: lockfile,
  #     client: client
  #   ).resolve
  #   resolution.find("rails/conventions").version
  #
  # @since 0.1.0
  class Resolver # rubocop:disable Metrics/ClassLength
    # Raised when a declared skill cannot be resolved to a published version.
    class Error < RubySkills::Error; end

    # @param skillfile [Skillfile]
    # @param client [Registry::Client]
    # @param lockfile [Lockfile, nil]
    # @param update [Boolean, String] +true+ re-resolves every skill; a name
    #   re-resolves only that skill and keeps every other lock pin
    def initialize(skillfile:, client:, lockfile: nil, update: false)
      @skillfile = skillfile
      @client = client
      @lockfile = lockfile
      @update = update
    end

    # @return [Resolution]
    # @raise [Error]
    def resolve
      skills = @skillfile.dependencies.map { |dependency| resolve_dependency(dependency) }

      Resolution.new(
        source: @skillfile.source,
        skills: skills,
        dependencies: @skillfile.dependencies
      )
    end

    private

    # @param dependency [Dependency]
    # @return [ResolvedSkill]
    def resolve_dependency(dependency)
      locked = locked_skill(dependency)
      return fetch_release(dependency, locked.version) if keep_locked?(dependency, locked)

      resolve_latest(dependency)
    end

    # @param dependency [Dependency]
    # @return [LockedSkill, nil]
    def locked_skill(dependency)
      return if @lockfile.nil? || updating?(dependency)

      @lockfile.find(dependency.name)
    end

    # @param dependency [Dependency]
    # @return [Boolean]
    def updating?(dependency)
      @update == true || @update == dependency.name
    end

    # @param dependency [Dependency]
    # @param locked [LockedSkill, nil]
    # @return [Boolean]
    def keep_locked?(dependency, locked)
      return false if locked.nil?
      return false unless dependency.requirement.satisfied_by?(locked.version)

      available_release?(fetch_version(dependency.name, locked.version))
    end

    # @param dependency [Dependency]
    # @return [ResolvedSkill]
    def resolve_latest(dependency)
      skill = load_skill(dependency.name)
      candidates = compatible_versions(skill.versions, dependency.requirement)

      candidates.each do |version|
        release = fetch_version(dependency.name, version)
        return to_resolved(dependency, release) if available_release?(release)
      end

      raise unsatisfiable_error(dependency)
    end

    # @param dependency [Dependency]
    # @param version [Gem::Version]
    # @return [ResolvedSkill]
    def fetch_release(dependency, version)
      release = fetch_version(dependency.name, version)
      raise unsatisfiable_error(dependency) unless available_release?(release)

      to_resolved(dependency, release)
    end

    # @param name [String]
    # @return [Registry::Skill]
    def load_skill(name)
      @client.get_skill(name)
    rescue Registry::Error => e
      raise Error, "Could not find skill #{name} in the registry" if not_found?(e)

      raise Error, "Failed to resolve #{name}: #{e.message}"
    end

    # @param name [String]
    # @param version [Gem::Version, String]
    # @return [Registry::Version, nil]
    def fetch_version(name, version)
      @client.get_version(name, version.to_s)
    rescue Registry::Error => e
      return if not_found?(e)

      raise Error, "Failed to resolve #{name} (#{version}): #{e.message}"
    end

    # @param versions [Array<String>]
    # @param requirement [Gem::Requirement]
    # @return [Array<Gem::Version>] highest first
    def compatible_versions(versions, requirement)
      versions
        .select { |value| Gem::Version.correct?(value) }
        .map { |value| Gem::Version.new(value) }
        .select { |version| requirement.satisfied_by?(version) }
        .sort
        .reverse
    end

    # @param release [Registry::Version, nil]
    # @return [Boolean]
    def available_release?(release)
      return false if release.nil?
      return false if release.yanked
      return false if unpublished?(release)

      true
    end

    # @param release [Registry::Version]
    # @return [Boolean]
    def unpublished?(release)
      release.published_at.nil? || release.published_at == false
    end

    # @param dependency [Dependency]
    # @param release [Registry::Version]
    # @return [ResolvedSkill]
    def to_resolved(dependency, release)
      if blank?(release.checksum)
        raise Error, "Missing checksum for #{dependency.name} (#{release.version})"
      end

      ResolvedSkill.new(
        name: dependency.name,
        version: release.version,
        checksum: release.checksum,
        source: @skillfile.source,
        download_url: release.download_url
      )
    end

    # @param error [Registry::Error]
    # @return [Boolean]
    def not_found?(error)
      error.code == "not_found" || error.status == 404
    end

    # @param value [String, nil]
    # @return [Boolean]
    def blank?(value)
      value.to_s.strip.empty?
    end

    # @param dependency [Dependency]
    # @return [Error]
    def unsatisfiable_error(dependency)
      Error.new(
        "Could not find a version of #{dependency.name} that satisfies " \
        "#{dependency.requirement}"
      )
    end
  end
end
