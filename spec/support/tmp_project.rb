# frozen_string_literal: true

module RubySkillsSpec
  # Builds an isolated project root so specs do not touch the gem checkout.
  module TmpProject
    # Yield a temporary directory as the current working directory.
    #
    # @yieldparam root [Pathname]
    # @return [void]
    def with_tmp_project
      Dir.mktmpdir("ruby-skills-spec-") do |dir|
        root = Pathname.new(dir)

        Dir.chdir(root) do
          yield root
        end
      end
    end
  end
end
