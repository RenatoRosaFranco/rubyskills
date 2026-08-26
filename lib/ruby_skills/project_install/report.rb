# frozen_string_literal: true

module RubySkills
  class ProjectInstall
    # Stdout reporter for {ProjectInstall}.
    #
    # @api private
    class Report
      # @param io [#puts]
      def initialize(io)
        @io = io
      end

      # @return [void]
      def reading
        @io.puts "Reading Skillfile..."
        @io.puts
      end

      # @return [void]
      def resolving
        @io.puts "Resolving skills..."
        @io.puts
      end

      # @param skill [ResolvedSkill]
      # @return [void]
      def using(skill)
        @io.puts "Using #{skill.name} #{skill.version}"
      end

      # @param skill [ResolvedSkill]
      # @return [void]
      def fetching(skill)
        @io.puts "Fetching #{skill.name} #{skill.version}"
      end

      # @param skill [ResolvedSkill]
      # @return [void]
      def installing(skill)
        @io.puts "Installing #{skill.name} #{skill.version}"
      end

      # @return [void]
      def adding(name)
        @io.puts "Adding #{name} to Skillfile..."
        @io.puts
      end

      # @param dependency [Dependency]
      # @return [void]
      def already_declared(dependency)
        @io.puts "#{dependency.name} is already declared in Skillfile " \
                 "(#{dependency.requirement})"
      end

      # @return [void]
      def resolving_dependencies
        @io.puts "Resolving dependencies..."
      end

      # @return [void]
      def checksums_verified
        @io.puts
        @io.puts "✓ checksums verified"
      end

      # @return [void]
      def installed_ok
        @io.puts "✓ installed"
      end

      # @return [void]
      def skillfile_updated
        @io.puts "✓ Skillfile updated"
      end

      # @return [void]
      def lock_updated
        @io.puts "✓ Skills.lock updated"
        @io.puts
      end

      # @param name [String]
      # @param requirement [Gem::Requirement]
      # @return [void]
      def added(name, requirement)
        @io.puts "Added #{name} (#{requirement})"
      end

      # @return [void]
      def writing_lock
        @io.puts
        @io.puts "Writing Skills.lock"
        @io.puts
      end

      # @param count [Integer]
      # @return [void]
      def installed(count)
        noun = count == 1 ? "skill" : "skills"
        @io.puts "Installed #{count} #{noun}."
      end

      # @return [void]
      def up_to_date
        @io.puts "All skills are up to date with Skills.lock."
      end
    end
  end
end
