# frozen_string_literal: true

RSpec.describe RubySkills::RequestedSkill do
  describe ".parse" do
    it "parses a registry name without a requirement" do
      requested = described_class.parse("rails/request-specs")

      expect(requested.name).to eq("rails/request-specs")
      expect(requested.requirement_string).to be_nil
      expect(requested).not_to be_explicit
    end

    it "parses @version as an exact requirement" do
      requested = described_class.parse("rails/request-specs@2.1.4")

      expect(requested.name).to eq("rails/request-specs")
      expect(requested.requirement_string).to eq("= 2.1.4")
      expect(requested).to be_explicit
    end

    it "parses --version as the given requirement" do
      requested = described_class.parse("rails/request-specs", version: "~> 2.0")

      expect(requested.requirement_string).to eq("~> 2.0")
      expect(requested).to be_explicit
    end

    it "rejects @version combined with --version" do
      expect {
        described_class.parse("rails/request-specs@2.1.4", version: "~> 2.0")
      }.to raise_error(RubySkills::Error, "Pass either @version or --version, not both")
    end

    it "rejects an invalid skill name" do
      expect {
        described_class.parse("request-specs")
      }.to raise_error(RubySkills::Error, %r{must be namespace/name})
    end

    it "rejects an invalid @version" do
      expect {
        described_class.parse("rails/request-specs@not-a-version")
      }.to raise_error(RubySkills::Error, /Invalid version/)
    end

    it "rejects an invalid --version requirement" do
      expect {
        described_class.parse("rails/request-specs", version: "not a requirement")
      }.to raise_error(RubySkills::Error, /Invalid version requirement/)
    end
  end
end
