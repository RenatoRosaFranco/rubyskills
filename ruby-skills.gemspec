# frozen_string_literal: true

require_relative "lib/ruby_skills/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-skills"
  spec.version = RubySkills::VERSION
  spec.authors = ["Renato Franco"]

  spec.summary = "Package manager for Ruby and Rails development skills"
  spec.description = <<~DESCRIPTION
    Ruby Skills provides a package management layer for installing,
    updating, removing and sharing IA development skills for Ruby
    and Ruby on Rails projects.
  DESCRIPTION

  spec.homepage = "https://github.com/renatofranco/ruby-skills"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir[
    "lib/**/*",
    "bin/*",
    "README.md",
    "LICENSE"
  ]

  spec.bindir = "bin"
  spec.executables = ["ruby-skills"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "yard", "~> 0.9"
end