# frozen_string_literal: true

require "pathname"

module RubySkills
  # Legacy Skillfile used by {Installer} / {Updater} (github/path sources).
  #
  # The project-level registry Skillfile is {RubySkills::Skillfile}.
  #
  # @api private
  # @since 0.1.0
  class LegacySkillfile
    # Declared skill entry loaded from a legacy Skillfile.
    #
    # @!attribute [rw] name
    #   @return [String] skill identifier
    # @!attribute [rw] github
    #   @return [String, nil] GitHub repository in +owner/name+ form
    # @!attribute [rw] path
    #   @return [String, nil] local filesystem path to the skill
    # @!attribute [rw] version
    #   @return [String, nil] optional pinned version
    Skill = Struct.new(
      :name,
      :github,
      :path,
      :version,
      keyword_init: true
    )

    # @return [Array<Skill>] skills declared in the Skillfile
    attr_reader :skills

    # @param path [Pathname, String] path to the Skillfile
    def initialize(path: default_skill_path)
      @path = Pathname.new(path)
      @skills = []
    end

    # Read and evaluate the Skillfile, populating {#skills}.
    #
    # @return [LegacySkillfile] self
    # @raise [RubySkills::Error] if the Skillfile is missing or invalid
    def load!
      unless @path.exist?
        raise RubySkills::Error,
              "Skillfile not found. Run `ruby-skills init` first."
      end

      instance_eval(@path.read, @path.to_s, 1)

      self
    rescue SyntaxError => e
      raise RubySkills::Error, "Invalid Skillfile: #{e.message}"
    end

    # Declare a skill in the Skillfile DSL.
    #
    # Exactly one source must be provided: +github+ or +path+.
    #
    # @param name [String] skill identifier
    # @param github [String, nil] GitHub repository in +owner/name+ form
    # @param path [String, nil] local filesystem path to the skill
    # @param version [String, nil] optional pinned version
    # @return [void]
    # @raise [RubySkills::Error] if neither +github+ nor +path+ is given
    def skill(name, github: nil, path: nil, version: nil)
      unless github || path
        raise RubySkills::Error,
              "#{name}: either github or path: must be provided"
      end

      @skills << Skill.new(
        name: name,
        github: github,
        path: path,
        version: version
      )
    end

    private

    # @api private
    # @return [Pathname] default path used when none is given to {#initialize}
    def default_skill_path
      Config.new.skillfile_path
    end
  end
end
