# frozen_string_literal: true

require "rubygems"

module RubySkills
  # Resolves every Skillfile dependency, including the transitive graph.
  #
  # Direct Skillfile requirements are combined with requirements declared by
  # selected SkillVersions. One version is chosen per skill: the highest
  # `Gem::Version` that satisfies every requirement, unless a still-valid
  # Skills.lock pin is kept (install is not update).
  #
  # Yanked and unpublished releases are ignored. Registry metadata is cached
  # for the session. Nothing is downloaded or written.
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
      @catalog = Catalog.new(client)
      @terms = Hash.new { |hash, key| hash[key] = [] }
      @selected = {}
      @stack = []
    end

    # @return [Resolution]
    # @raise [ResolutionError]
    def resolve
      @skillfile.dependencies.each do |dependency|
        add_term(Term.new(name: dependency.name, requirement: dependency.requirement))
      end

      search_remaining

      Resolution.new(
        source: @skillfile.source,
        skills: finalized_skills,
        dependencies: @skillfile.dependencies
      )
    end

    private

    # @param name [String]
    # @return [void]
    def decide(name)
      raise CircularDependency, @stack + [name] if @stack.include?(name)
      return if selected_compatible?(name)

      try_versions(name)
    end

    # @param name [String]
    # @return [void]
    def try_versions(name)
      last_error = nil
      versions = candidate_versions(name)
      raise incompatibility_error(name) if versions.empty?

      resolved = false
      versions.each do |version|
        snapshot = snapshot_state
        begin
          assign_with_deps!(name, version)
          search_remaining
          resolved = true
          break
        rescue ResolutionError => e
          raise if e.is_a?(SkillNotFound)

          last_error = e
          restore_state(snapshot)
        end
      end

      return if resolved

      raise last_error || incompatibility_error(name)
    end

    # @param name [String]
    # @param version [Gem::Version]
    # @return [void]
    def assign_with_deps!(name, version)
      @stack.push(name)
      assign!(name, version)
      dependencies_of(@selected[name]).each do |dependency|
        add_term(
          Term.new(
            name: dependency.name,
            requirement: dependency.requirement,
            parent_name: name
          )
        )
        decide(dependency.name)
      end
    ensure
      @stack.pop if @stack.last == name
    end

    # @return [void]
    def search_remaining
      loop do
        name = next_unresolved
        break unless name

        decide(name)
      end
    end

    # @return [String, nil]
    def next_unresolved
      @terms.keys.sort.find { |name| !selected_compatible?(name) }
    end

    # @param name [String]
    # @param version [Gem::Version]
    # @return [void]
    def assign!(name, version)
      retract_parent_terms!(name)
      release = @catalog.version(name, version)
      unless available_release?(release)
        raise NoCompatibleVersion,
              "Could not find a version of #{name} that satisfies " \
              "#{requirement_label(name)}"
      end
      if blank?(release.checksum)
        raise ResolutionError, "Missing checksum for #{name} (#{release.version})"
      end

      @selected[name] = build_resolved(name, release)
    end

    # Drop requirements introduced by a previous version of +name+.
    #
    # @param name [String]
    # @return [void]
    def retract_parent_terms!(name)
      @terms.each_key do |dep_name|
        @terms[dep_name].reject! { |term| term.parent_name == name }
      end
      @terms.delete_if { |_dep_name, terms| terms.empty? }
    end

    # @param term [Term]
    # @return [void]
    def add_term(term)
      @terms[term.name] << term
    end

    # @param name [String]
    # @return [Array<Gem::Version>]
    def candidate_versions(name)
      listed = listed_versions(name).select { |version| terms_satisfied?(name, version) }
      locked = preferred_lock(name)
      if locked && listed.include?(locked)
        return [locked] + listed.reject { |version| version == locked }
      end

      listed
    end

    # @param name [String]
    # @return [Array<Gem::Version>] highest first
    def listed_versions(name)
      listed = @catalog.skill(name).versions.filter_map { |value|
        next unless Gem::Version.correct?(value)

        Gem::Version.new(value)
      }
      listed.uniq.sort.reverse
    end

    # @param name [String]
    # @return [Gem::Version, nil]
    def preferred_lock(name)
      return if updating?(name)

      locked = @lockfile&.find(name)
      return unless locked
      return unless terms_satisfied?(name, locked.version)

      locked.version
    end

    # @param name [String]
    # @return [Boolean]
    def updating?(name)
      @update == true || @update == name
    end

    # @param name [String]
    # @param version [Gem::Version]
    # @return [Boolean]
    def terms_satisfied?(name, version)
      @terms[name].all? { |term| term.requirement.satisfied_by?(version) }
    end

    # @param name [String]
    # @return [Boolean]
    def selected_compatible?(name)
      selected = @selected[name]
      selected && terms_satisfied?(name, selected.version)
    end

    # @param skill [ResolvedSkill]
    # @return [Array<Dependency>]
    def dependencies_of(skill)
      Array(skill.dependencies)
    end

    # @param name [String]
    # @param release [Registry::Version]
    # @return [ResolvedSkill]
    def build_resolved(name, release)
      ResolvedSkill.new(
        name: name,
        version: release.version,
        checksum: release.checksum,
        source: @skillfile.source,
        download_url: release.download_url,
        dependencies: parse_release_dependencies(release)
      )
    end

    # @param release [Registry::Version]
    # @return [Array<Dependency>]
    def parse_release_dependencies(release)
      Array(release.dependencies).filter_map { |row| dependency_from(row) }
    end

    # @param row [Dependency, Hash, #name]
    # @return [Dependency, nil]
    def dependency_from(row)
      if row.is_a?(Dependency)
        row
      elsif row.is_a?(Hash)
        name = row["name"] || row[:name]
        return if name.to_s.strip.empty?

        Dependency.new(name: name.to_s, requirement: requirement_from(row))
      elsif row.respond_to?(:name)
        Dependency.new(name: row.name, requirement: requirement_from(row))
      end
    end

    # @param row [Hash, #requirement]
    # @return [Gem::Requirement]
    def requirement_from(row)
      value = if row.is_a?(Hash)
                row["requirement"] || row[:requirement]
              else
                row.requirement
              end
      return value if value.is_a?(Gem::Requirement)

      Gem::Requirement.new(value.nil? || value.to_s.strip.empty? ? ">= 0" : value)
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

    # @param value [String, nil]
    # @return [Boolean]
    def blank?(value)
      value.to_s.strip.empty?
    end

    # @return [Hash]
    def snapshot_state
      {
        selected: @selected.dup,
        terms: @terms.transform_values(&:dup)
      }
    end

    # @param snapshot [Hash]
    # @return [void]
    def restore_state(snapshot)
      @selected = snapshot[:selected].dup
      @terms = Hash.new { |hash, key| hash[key] = [] }
      snapshot[:terms].each { |name, terms| @terms[name] = terms.dup }
    end

    # @param name [String]
    # @return [ResolutionError]
    def incompatibility_error(name)
      terms = @terms[name]
      if terms.size > 1
        VersionConflict.new(name, terms)
      else
        NoCompatibleVersion.new(
          "Could not find a version of #{name} that satisfies #{requirement_label(name)}"
        )
      end
    end

    # @param name [String]
    # @return [String]
    def requirement_label(name)
      terms = @terms[name]
      return Gem::Requirement.default.to_s if terms.empty?
      return terms.first.requirement.to_s if terms.size == 1

      terms.map { |term| term.requirement.to_s }.join(", ")
    end

    # @return [Array<ResolvedSkill>]
    def finalized_skills
      reachable_names.sort.filter_map { |name|
        skill = @selected[name]
        next unless skill

        ResolvedSkill.new(
          name: skill.name,
          version: skill.version,
          checksum: skill.checksum,
          source: skill.source,
          download_url: skill.download_url,
          dependencies: skill.dependencies,
          required_by: Array(@terms[name]).sort_by { |term|
            [term.source_label, term.requirement.to_s]
          }
        )
      }
    end

    # @return [Array<String>]
    def reachable_names
      queue = @skillfile.dependencies.map(&:name)
      seen = []
      until queue.empty?
        name = queue.shift
        next if seen.include?(name)

        seen << name
        skill = @selected[name]
        next unless skill

        dependencies_of(skill).each { |dependency| queue << dependency.name }
      end
      seen
    end
  end
end
