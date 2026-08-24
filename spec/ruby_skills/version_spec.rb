# frozen_string_literal: true

RSpec.describe "RubySkills::VERSION" do
  it "is a semver string" do
    expect(RubySkills::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
