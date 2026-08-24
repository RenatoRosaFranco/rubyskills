# frozen_string_literal: true

RSpec.describe RubySkills::Updater do
  describe "#update" do
    it "reinstalls a single skill and prints a confirmation" do
      installer = instance_double(RubySkills::Installer)
      allow(RubySkills::Installer).to receive(:new).and_return(installer)
      allow(installer).to receive(:install)

      expect {
        described_class.new.update("rails-performance")
      }.to output("✓ Updated rails-performance\n").to_stdout

      expect(installer).to have_received(:install).with("rails-performance")
    end

    it "reinstalls every skill when no name is given" do
      installer = instance_double(RubySkills::Installer)
      allow(RubySkills::Installer).to receive(:new).and_return(installer)
      allow(installer).to receive(:install)

      expect {
        described_class.new.update
      }.to output("✓ All skills updated\n").to_stdout

      expect(installer).to have_received(:install).with(nil)
    end
  end
end
