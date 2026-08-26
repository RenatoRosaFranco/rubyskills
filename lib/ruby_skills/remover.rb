# frozen_string_literal: true

module RubySkills
  # Uninstalls a skill from the project, adapters, and lockfile.
  #
  # @example Remove an installed skill
  #   RubySkills::Remover.new.remove("rails-performance")
  #
  # @see RubySkills::LegacyLockfile
  # @see RubySkills::Adapters
  # @since 0.1.0
  class Remover
    # @param config [RubySkills::Config] project paths used to locate skills
    def initialize(config: Config.new)
      @config = config
    end

    # Remove an installed skill from disk, tool adapters, and the lockfile.
    #
    # @param name [String] skill identifier to remove
    # @return [void]
    # @raise [RubySkills::Error] if the skill is not installed
    def remove(name)
      path = @config.skills_path.join(name)

      unless path.exist?
        raise RubySkills::Error,
              "Skill `#{name}` is not installed"
      end

      adapters.each do |adapter|
        adapter.new.remove(name)
      end

      FileUtils.rm_rf(path)

      LegacyLockfile.new.remove(name)

      puts "✓ Removed #{name}"
    end

    private

    # @api private
    # @return [Array<Class>] adapter classes notified when a skill is removed
    def adapters
      RubySkills::Adapters.all
    end
  end
end
