# frozen_string_literal: true

require "tmpdir"

module RubySkills
  # Turns a declared skill into a local directory that can be installed.
  #
  # Local skills are resolved from {RubySkills::Manifest::Skill#path}.
  # Remote skills are cloned from GitHub into a temporary directory.
  #
  # @example Resolve a declared skill
  #   skill = RubySkills::Manifest::Skill.new(name: "rails-performance", path: "./skills/rails-performance")
  #   RubySkills::Resolver.new.resolve(skill)
  #
  # @see RubySkills::Manifest::Skill
  # @since 0.1.0
  class Resolver
    # Skill directory ready to be installed.
    #
    # @!attribute [rw] name
    #   @return [String] skill identifier
    # @!attribute [rw] path
    #   @return [Pathname] local directory containing the skill
    # @!attribute [rw] source
    #   @return [String] origin used to resolve the skill
    ResolvedSkill = Struct.new(
      :name,
      :path,
      :source,
      keyword_init: true
    )

    # Resolve a skill from a local path or a remote repository.
    #
    # @param skill [RubySkills::Manifest::Skill] declared skill to resolve
    # @return [ResolvedSkill] skill directory ready to install
    # @raise [RubySkills::Error] if the skill has no usable source
    def resolve(skill)
      if skill.path
        resolve_local(skill)
      elsif skill.github
        resolve_remote(skill)
      else
        raise RubySkills::Error,
              "Unable to resolve #{skill.name}"
      end
    end

    private

    # @api private
    # @param skill [RubySkills::Manifest::Skill]
    # @return [ResolvedSkill]
    # @raise [RubySkills::Error] if the local skill path is not a directory
    def resolve_local(skill)
      path = Pathname.new(skill.path).expand_path

      unless path.directory?
        raise RubySkills::Error,
              "Skill path does not exist: #{path}"
      end

      ResolvedSkill.new(
        name: skill.name,
        path: path,
        source: "path:#{path}"
      )
    end

    # @api private
    # @param skill [RubySkills::Manifest::Skill]
    # @return [ResolvedSkill] skill cloned into a temporary directory
    # @raise [RubySkills::Error] if the GitHub repository cannot be cloned
    def resolve_remote(skill)
      directory = Pathname.new(
        Dir.mktmpdir("ruby-skills")
      )

      repository = "https://github.com/#{skill.github}.git"

      success = system(
        "git",
        "clone",
        "--depth",
        "1",
        repository,
        directory.to_s,
        out: File::NULL,
        err: File::NULL
      )

      unless success
        raise RubySkills::Error,
              "Unable to clone #{skill.github}"
      end

      ResolvedSkill.new(
        name: skill.name,
        path: directory,
        source: "github:#{skill.github}"
      )
    end
  end
end
