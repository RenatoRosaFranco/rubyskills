# frozen_string_literal: true

RSpec.describe RubySkills do
  it "defines a base error" do
    expect(RubySkills::Error).to be < StandardError
  end

  it "exposes the CLI" do
    expect(RubySkills::CLI).to be < Thor
  end
end
