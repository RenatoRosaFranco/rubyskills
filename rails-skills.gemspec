# frozen_string_literal: true

require_relative "lib/rails_skills"

Gem::Specification.new do |spec|
  spec.name = "rails-skills"
  spec.version = RailsSkills::VERSION
  spec.authors = ["Renato Franco"]

  spec.summary = "Package manager for Ruby and Rails development skills"
  spec.description <<~DESCRIPTION
    Rails skills provides a package management layer for installing,
    updating, removing and sharing IA development skills for Ruby
    and Ruby on Rails projects.
  DESCRIPTION

  spec.homepage = "https://github.com/renatofranco/rails-skills"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir[
    "lib/**/*",
    "bin/*",
    "README.md",
    "LICENSE"
  ]

  spec.bindir = "bin"
  spec.executables = ["rails-skills"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
end