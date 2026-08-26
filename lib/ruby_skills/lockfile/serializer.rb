# frozen_string_literal: true

module RubySkills
  class Lockfile
    # Deterministic Skills.lock renderer.
    #
    # @api private
    class Serializer
      # @param lockfile [Lockfile]
      def initialize(lockfile)
        @lockfile = lockfile
      end

      # @return [String] always ends with a newline
      def to_s
        lines = ["RUBY SKILLS", "  remote: #{@lockfile.source}", ""]
        @lockfile.skills.each do |skill|
          lines << "  #{skill.name} (#{skill.version})"
          lines << "    sha256: #{skill.checksum.delete_prefix("sha256:")}"
          lines << ""
        end
        lines << "DEPENDENCIES"
        @lockfile.dependencies.each do |dependency|
          lines << "  #{dependency.name} (#{dependency.requirement})"
        end
        "#{lines.join("\n")}\n"
      end
    end
  end
end
