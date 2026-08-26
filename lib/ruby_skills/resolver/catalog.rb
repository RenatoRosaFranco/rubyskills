# frozen_string_literal: true

module RubySkills
  class Resolver
    # Session cache for registry metadata. One HTTP fetch per skill and per
    # skill version during a resolve.
    class Catalog
      # @param client [Registry::Client]
      def initialize(client)
        @client = client
        @skills = {}
        @versions = {}
      end

      # @param name [String]
      # @return [Registry::Skill]
      def skill(name)
        return @skills[name] if @skills.key?(name)

        @skills[name] = @client.get_skill(name)
      rescue Registry::Error => e
        raise SkillNotFound, "Could not find skill #{name} in the registry" if not_found?(e)

        raise ResolutionError, "Failed to resolve #{name}: #{e.message}"
      end

      # @param name [String]
      # @param version [Gem::Version, String]
      # @return [Registry::Version, nil]
      def version(name, version)
        key = [name, version.to_s]
        return @versions[key] if @versions.key?(key)

        @versions[key] = @client.get_version(name, version.to_s)
      rescue Registry::Error => e
        return @versions[key] = nil if not_found?(e)

        raise ResolutionError, "Failed to resolve #{name} (#{version}): #{e.message}"
      end

      private

      # @param error [Registry::Error]
      # @return [Boolean]
      def not_found?(error)
        error.code == "not_found" || error.status == 404
      end
    end
  end
end
