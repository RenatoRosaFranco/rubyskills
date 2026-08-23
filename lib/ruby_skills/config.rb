# frozen_string_literal: true

module RubySkills
  # Resolves project paths and bootstraps a Ruby Skills workspace.
  #
  # Paths for +Skillfile+, +Skills.lock+ and the local skills directory
  # are derived from a project root.
  #
  # @example Initialize the current directory
  #   RubySkills::Config.new.initialize_project!
  #
  # @since 0.1.0
  class Config
    # Filename of the project skill manifest.
    SKILLFILE = "Skillfile"

    # Filename of the installed-skills lockfile.
    LOCKFILE = "Skills.lock"

    # Directory where installed skills are stored.
    SKILLS_DIRECTORY = ".ruby-skills"

    # @param root [String, Pathname] project root used to resolve skill paths
    def initialize(root: Dir.pwd)
      @root = Pathname.new(root)
    end

    # Create the skills directory and a starter Skillfile when missing.
    #
    # @return [void]
    def initialize_project!
      create_skills_directory
      create_skillfile
    end

    # @return [Pathname] absolute path to the project Skillfile
    def skillfile_path
      @root.join(SKILLFILE)
    end

    # @return [Pathname] absolute path to the project lockfile
    def lockfile_path
      @root.join(LOCKFILE)
    end

    # @return [Pathname] absolute path to the local skills directory
    def skills_path
      @root.join(SKILLS_DIRECTORY)
    end

    private

    # @api private
    # @return [void]
    def create_skills_directory
      FileUtils.mkdir_p(skills_path)
    end

    # @api private
    # @return [void]
    def create_skillfile
      return if skillfile_path.exist?

      skillfile_path.write(<<~RUBY)
        # Ruby Skills

        # skill "rails-performance",
        #   github: "username/rails-performance"
      RUBY
    end
  end
end
