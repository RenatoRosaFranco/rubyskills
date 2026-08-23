# frozen_string_literal: true

module RubySkills
  # Reinstalls skills to pick up newer versions.
  #
  # Delegates the work to {RubySkills::Installer}. When +skill_name+ is
  # omitted, every skill in the Skillfile is updated.
  #
  # @example Update a single skill
  #   RubySkills::Updater.new.update("rails-performance")
  #
  # @example Update every declared skill
  #   RubySkills::Updater.new.update
  #
  # @see RubySkills::Installer
  # @since 0.1.0
  class Updater
    # Update one skill or every skill declared in the Skillfile.
    #
    # @param skill_name [String, nil] skill to update, or +nil+ to update all
    # @return [void]
    def update(skill_name = nil)
      Installer.new.install(skill_name)

      if skill_name
        puts "✓ Updated #{skill_name}"
      else
        puts "✓ All skills updated"
      end
    end
  end
end
