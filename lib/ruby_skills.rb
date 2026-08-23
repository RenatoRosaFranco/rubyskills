# frozen_string_literal: true

require "yaml"
require "fileutils"
require "pathname"

# Package manager for installing, updating, removing and sharing AI
# development skills in Ruby and Rails projects.
#
# @see RubySkills::CLI
# @see RubySkills::Config
# @since 0.1.0
module RubySkills
  # Base error for all Ruby Skills failures.
  class Error < StandardError; end
end

Dir.glob("ruby_skills/**/*.rb", base: __dir__).sort.each do |path|
  require path.delete_suffix(".rb")
end