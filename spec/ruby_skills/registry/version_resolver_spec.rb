# frozen_string_literal: true

RSpec.describe RubySkills::Registry::VersionResolver do
  def resolve(versions, requirement)
    described_class.new(versions, requirement).resolve
  end

  it "selects the highest Gem version for latest" do
    expect(resolve(%w[1.9.0 1.10.0 2.0.0], "latest")).to eq("2.0.0")
    expect(resolve(%w[1.9.0 1.10.0], "LATEST")).to eq("1.10.0")
  end

  it "resolves pessimistic and comparison requirements" do
    versions = %w[1.9.0 1.10.0 2.0.0]

    expect(resolve(versions, "~> 1.0")).to eq("1.10.0")
    expect(resolve(versions, ">= 2.0")).to eq("2.0.0")
    expect(resolve(versions, [">= 1.9", "< 1.10"])).to eq("1.9.0")
  end

  it "returns nil when nothing matches or the requirement is invalid" do
    expect(resolve(%w[1.9.0 1.10.0], "~> 3.0")).to be_nil
    expect(resolve(%w[1.9.0], "not-a-version")).to be_nil
    expect(resolve(%w[1.9.0], "")).to be_nil
    expect(resolve([], "latest")).to be_nil
  end

  it "does not select a prerelease unless the requirement asks for one" do
    expect(resolve(%w[1.0.0.pre 0.9.0], ">= 1.0")).to be_nil
    expect(resolve(%w[1.0.0.pre 0.9.0], ">= 1.0.0.pre")).to eq("1.0.0.pre")
  end
end
