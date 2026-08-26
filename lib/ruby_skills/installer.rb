# frozen_string_literal: true

module RubySkills
  # Installs skills declared in the Skillfile.
  #
  # Resolves each skill, copies it into +.ruby-skills+, notifies tool
  # adapters, and records the result in +Skills.lock+.
  #
  # @example Install every declared skill
  #   RubySkills::Installer.new.install
  #
  # @example Install one skill
  #   RubySkills::Installer.new.install("rails-performance")
  #
  # @see RubySkills::LegacySkillfile
  # @see RubySkills::Resolver
  # @since 0.1.0
  class Installer
    # @param config [RubySkills::Config] project paths used during install
    def initialize(config: Config.new)
      @config = config
    end

    # Install one skill or every skill declared in the Skillfile.
    #
    # @param skill_name [String, nil] skill to install, or +nil+ to install all
    # @return [void]
    # @raise [RubySkills::Error] if the Skillfile is missing or a skill cannot be installed
    def install(skill_name = nil)
      load_skills(skill_name).each do |skill|
        install_skill(skill)
      end
    end

    private

    # @api private
    # @param skill_name [String, nil]
    # @return [Array<RubySkills::LegacySkillfile::Skill>]
    # @raise [RubySkills::Error] if the named skill is not in the Skillfile
    def load_skills(skill_name)
      skillfile = LegacySkillfile.new.load!

      return skillfile.skills if skill_name.nil?

      skill = skillfile.skills.find { |declared| declared.name == skill_name }
      raise RubySkills::Error, "Skill `#{skill_name}` is not in the Skillfile" unless skill

      [skill]
    end

    # @api private
    # @param skill [RubySkills::LegacySkillfile::Skill]
    # @return [void]
    def install_skill(skill)
      resolved = Resolver.new.resolve(skill)
      destination = @config.skills_path.join(resolved.name)

      FileUtils.rm_rf(destination)
      FileUtils.mkdir_p(@config.skills_path)
      FileUtils.cp_r(resolved.path, destination)

      adapters.each do |adapter|
        adapter.new.install(resolved.name, destination)
      end

      Lockfile.new(config: @config).add(
        resolved.name,
        version: skill.version || "unspecified",
        source: resolved.source
      )

      puts "✓ Installed #{resolved.name}"
    end

    # @api private
    # @return [Array<Class>] adapter classes notified when a skill is installed
    def adapters
      [
        Adapters::Claude,
        Adapters::Codex,
        Adapters::Cursor,
        Adapters::Vscode
      ]
    end
  end
end
