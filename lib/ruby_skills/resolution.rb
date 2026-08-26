# frozen_string_literal: true

module RubySkills
  # Exact versions chosen for every {Skillfile} dependency.
  #
  # Does not install files or write +Skills.lock+.
  #
  # @since 0.1.0
  class Resolution
    # @return [String]
    attr_reader :source

    # @return [Array<ResolvedSkill>]
    attr_reader :skills

    # @return [Array<Dependency>] declared Skillfile requirements
    attr_reader :dependencies

    # @param source [String]
    # @param skills [Array<ResolvedSkill>]
    # @param dependencies [Array<Dependency>]
    def initialize(source:, skills:, dependencies:)
      @source = source
      @skills = skills.sort_by(&:name).freeze
      @dependencies = dependencies.sort_by(&:name).freeze
    end

    # @param name [String]
    # @return [ResolvedSkill, nil]
    def find(name)
      @skills.find { |skill| skill.name == name }
    end

    # @return [Lockfile]
    def to_lockfile
      Lockfile.new(
        source: @source,
        skills: @skills.map { |skill|
          LockedSkill.new(name: skill.name, version: skill.version, checksum: skill.checksum)
        },
        dependencies: @dependencies
      )
    end
  end
end
