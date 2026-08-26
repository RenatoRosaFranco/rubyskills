# frozen_string_literal: true

require "ruby_skills"
require "fileutils"
require "json"
require "pathname"
require "tmpdir"
require "yaml"

Dir[File.expand_path("support/**/*.rb", __dir__)].each do |path|
  require path
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.include RubySkillsSpec::TmpProject
  config.include RubySkillsSpec::UserConfigHome
end
