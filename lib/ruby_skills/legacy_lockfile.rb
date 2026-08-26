# frozen_string_literal: true

require "yaml"

module RubySkills
  # Legacy YAML +Skills.lock+ used by {Installer} / {Remover} / +list+.
  #
  # The registry lockfile is {RubySkills::Lockfile}.
  #
  # @api private
  # @since 0.1.0
  class LegacyLockfile
    # @param config [RubySkills::Config] project paths used to locate Skills.lock
    def initialize(config: Config.new)
      @config = config
    end

    # Installed skills stored in the lockfile.
    #
    # @return [Hash{String => Hash}] skill names mapped to +version+ and +source+
    def skills
      return {} unless @config.lockfile_path.exist?

      data = YAML.safe_load_file(
        @config.lockfile_path,
        permitted_classes: [],
        aliases: true
      )

      data.fetch("skills", {})
    end

    # Record an installed skill in the lockfile.
    #
    # @param name [String] skill identifier
    # @param version [String] installed skill version
    # @param source [String] origin used to install the skill
    # @return [void]
    def add(name, version:, source:)
      data = load_data

      data["skills"][name] = {
        "version" => version,
        "source" => source
      }

      write(data)
    end

    # Drop a skill from the lockfile.
    #
    # @param name [String] skill identifier to remove
    # @return [void]
    def remove(name)
      data = load_data

      data["skills"].delete(name)

      write(data)
    end

    private

    # @api private
    # @return [Hash] lockfile payload with a +version+ header and +skills+ map
    def load_data
      {
        "version" => 1,
        "skills" => skills
      }
    end

    # @api private
    # @param data [Hash] lockfile payload to persist
    # @return [void]
    def write(data)
      @config.lockfile_path.write(
        YAML.dump(data)
      )
    end
  end
end
