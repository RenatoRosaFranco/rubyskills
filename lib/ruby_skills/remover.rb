# frozen_string_literal: true

module RubySkills
  # Uninstalls a skill from canonical +.ruby-skills+ storage.
  #
  # Direct removal does not modify Skillfile or Skills.lock. When the current
  # project's lock still references the skill, a warning is printed.
  #
  # @example
  #   RubySkills::Remover.new.remove("rails/request-specs")
  #
  # @see RubySkills::Install
  # @see RubySkills::Adapters
  # @since 0.1.0
  class Remover
    # @param config [RubySkills::Config] project paths used to locate skills
    # @param output [#puts]
    def initialize(config: nil, output: $stdout)
      @config = config || Config.new
      @output = output
    end

    # Remove installed versions of +name+ from +.ruby-skills+.
    #
    # @param name [String] +namespace/name+
    # @return [void]
    # @raise [RubySkills::Error] if a path is unsafe
    def remove(name)
      identifier = name.to_s.strip
      versions = Install.installed_versions(identifier, config: @config)
      if versions.empty?
        @output.puts "#{identifier} is not installed."
        return
      end

      versions.each do |version|
        @output.puts "Removing #{identifier} #{version}..."
      end
      @output.puts
      versions.each do |version|
        Install.remove_version!(identifier, version, config: @config)
      end
      @output.puts "✓ removed"
      warn_if_locked(identifier)
      sync_adapters(identifier)
    end

    private

    # @param name [String]
    # @return [void]
    def warn_if_locked(name)
      return unless lockfile_references?(name)

      @output.puts
      @output.puts "Warning:"
      @output.puts "#{name} is still referenced by this project's Skills.lock."
      @output.puts
      @output.puts "Run with --save to remove it from the project configuration."
    end

    # @param name [String]
    # @return [Boolean]
    def lockfile_references?(name)
      lockfile = nearest_lockfile
      return false if lockfile.nil?

      lockfile.locked?(name)
    end

    # @return [Lockfile, nil]
    def nearest_lockfile
      skillfile = Skillfile.find(@config.root)
      path = skillfile.path.dirname.join(Lockfile::FILENAME)
      return unless path.file?

      Lockfile.load(path)
    rescue RubySkills::Error
      nil
    end

    # @param name [String]
    # @return [void]
    def sync_adapters(name)
      Adapters.sync_remove(name, root: @config.root)
    rescue StandardError => e
      @output.puts
      @output.puts "Warning: adapter sync failed: #{e.message}"
    end
  end
end
