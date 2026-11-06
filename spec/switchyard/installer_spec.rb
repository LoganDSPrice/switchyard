# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "switchyard/installer"

RSpec.describe Switchyard::Installer do
  subject(:installer) { described_class.new(destination: temp_dir, runner: runner) }

  let(:temp_dir) { Dir.mktmpdir }
  let(:runner) { instance_double("Switchyard::ProcessRunner") }

  after do
    FileUtils.remove_entry(temp_dir)
  end

  describe "#install!" do
    context "when destination is a Rails project" do
      before do
        FileUtils.mkdir_p(File.join(temp_dir, "config"))
        File.write(File.join(temp_dir, "config", "database.yml"), "development:\n  database: test_dev\n")
        FileUtils.mkdir_p(File.join(temp_dir, "bin"))
      end

      it "generates binstubs in bin/ for dev, staging, production, and pr" do
        installer.install!

        %w[dev staging production pr].each do |binstub|
          path = File.join(temp_dir, "bin", binstub)
          expect(File.exist?(path)).to be true
          expect(File.stat(path).executable?).to be true
        end
      end

      it "creates a default .switchyard.yml configuration file" do
        installer.install!

        config_path = File.join(temp_dir, ".switchyard.yml")
        expect(File.exist?(config_path)).to be true
        expect(File.read(config_path)).to include("adapter: railway")
      end
    end

    context "when destination is not a Rails directory" do
      it "raises a NotInRailsProjectError" do
        expect {
          installer.install!
        }.to raise_error(Switchyard::Installer::NotInRailsProjectError, /Rails project/i)
      end
    end
  end
end
