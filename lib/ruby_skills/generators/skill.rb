# frozen_string_literal: true

require "fileutils"
require "pathname"

module RubySkills
  module Generators
    # Scaffolds a local Ruby Skill directory from +namespace/name+.
    #
    # @example Create a skill subdirectory
    #   RubySkills::Generators::Skill.new.create("rails/request-specs")
    #
    # @since 0.1.0
    class Skill
      # @!attribute [rw] directory
      #   @return [Pathname] created skill directory
      # @!attribute [rw] name
      #   @return [String] skill name
      # @!attribute [rw] namespace
      #   @return [String] skill namespace
      # @!attribute [rw] in_place
      #   @return [Boolean] whether files were written into +root+
      Result = Struct.new(:directory, :name, :namespace, :in_place, keyword_init: true)

      # @param root [String, Pathname] directory used as the generation root
      def initialize(root: Dir.pwd)
        @root = Pathname.new(root)
      end

      # Create skill files for +full_name+.
      #
      # @param full_name [String] +namespace/name+
      # @param in_place [Boolean] write into +root+ instead of a subdirectory
      # @return [Result]
      # @raise [RubySkills::Error] if the name is invalid or the target exists
      def create(full_name, in_place: false)
        namespace, name = parse_full_name(full_name)
        destination = in_place ? @root : @root.join(name)

        refuse_overwrite!(destination, in_place: in_place)
        write_files(destination, namespace: namespace, name: name)

        Result.new(
          directory: destination,
          name: name,
          namespace: namespace,
          in_place: in_place
        )
      end

      private

      # @api private
      # @param full_name [String]
      # @return [Array<String>]
      # @raise [RubySkills::Error] if +full_name+ is not +namespace/name+
      def parse_full_name(full_name)
        namespace, name, extra = full_name.to_s.split("/", 3)
        if extra || name.nil? || namespace.to_s.empty?
          raise RubySkills::Error,
                "Skill name must be namespace/name (e.g. rails/request-specs)"
        end

        validate_identifier!("namespace", namespace)
        validate_identifier!("name", name)

        [namespace, name]
      end

      # @api private
      # @param field [String]
      # @param value [String]
      # @return [void]
      # @raise [RubySkills::Error]
      def validate_identifier!(field, value)
        return if value.match?(Manifest::IDENTIFIER)

        raise RubySkills::Error,
              "#{field} must be lowercase and contain only letters, " \
              "numbers, '_' and '-'"
      end

      # @api private
      # @param destination [Pathname]
      # @param in_place [Boolean]
      # @return [void]
      # @raise [RubySkills::Error]
      def refuse_overwrite!(destination, in_place:)
        if in_place
          if destination.join(Manifest::FILENAME).exist?
            raise RubySkills::Error, "Refusing to overwrite existing skill.yml"
          end

          return
        end

        return unless destination.exist?

        raise RubySkills::Error, "Directory already exists: #{destination.basename}"
      end

      # @api private
      # @param destination [Pathname]
      # @param namespace [String]
      # @param name [String]
      # @return [void]
      def write_files(destination, namespace:, name:)
        FileUtils.mkdir_p(destination.join("references"))
        destination.join(Manifest::FILENAME).write(
          Templates::SkillYml.new(namespace: namespace, name: name).render
        )
        destination.join("SKILL.md").write(
          Templates::SkillMd.new(namespace: namespace, name: name).render
        )
      end
    end
  end
end
