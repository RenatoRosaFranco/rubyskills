# frozen_string_literal: true

require_relative "lib/ruby_skills/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-skills"
  spec.version = RubySkills::VERSION
  spec.authors = ["Renato Franco"]
  spec.email = ["renator.franco93@gmail.com"]

  spec.summary = "Package, share, and install Ruby engineering knowledge."
  spec.description = <<~DESCRIPTION
    Ruby Skills is a package manager for distributing engineering
    knowledge to Ruby development tools and coding agents.
  DESCRIPTION

  spec.homepage = "https://rubyskills.org"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/renatofranco/ruby-skills",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.chdir(__dir__) {
    `git ls-files -z`.split("\x0").reject do |file|
      file.start_with?(
        "test/",
        "spec/",
        "features/",
        ".git",
        ".github"
      )
    end
  }

  spec.bindir = "bin"
  spec.executables = ["ruby-skills"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.58"
  spec.add_development_dependency "rubocop-performance", "~> 1.20"
  spec.add_development_dependency "rubocop-rspec", "~> 3.0"
  spec.add_development_dependency "yard", "~> 0.9"
end
