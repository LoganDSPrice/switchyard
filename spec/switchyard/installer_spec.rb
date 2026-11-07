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

      it "generates binstubs in bin/ for switchyard, dev, staging, production, and pr" do
        installer.install!

        %w[switchyard dev staging production pr].each do |binstub|
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

      context "when git_safe option is enabled" do
        subject(:installer) { described_class.new(destination: temp_dir, runner: runner, git_safe: true) }

        it "creates .git/safe if destination is a git repository" do
          FileUtils.mkdir_p(File.join(temp_dir, ".git"))
          installer.install!

          expect(Dir.exist?(File.join(temp_dir, ".git", "safe"))).to be true
          expect(installer.git_safe_enabled?).to be true
        end

        it "does not raise if destination is not a git repository" do
          installer.install!

          expect(installer.git_safe_enabled?).to be false
        end
      end

      context "when git_safe option is disabled (default)" do
        it "does not create .git/safe even if destination is a git repository" do
          FileUtils.mkdir_p(File.join(temp_dir, ".git"))
          installer.install!

          expect(Dir.exist?(File.join(temp_dir, ".git", "safe"))).to be false
          expect(installer.git_safe_enabled?).to be false
        end
      end

      context "when github_action option is enabled" do
        subject(:installer) { described_class.new(destination: temp_dir, runner: runner, github_action: true) }

        it "creates .github/workflows/switchyard-cleanup-pr.yml" do
          installer.install!

          workflow_path = File.join(temp_dir, ".github", "workflows", "switchyard-cleanup-pr.yml")
          expect(File.exist?(workflow_path)).to be true
          expect(File.read(workflow_path)).to include("Switchyard Cleanup PR Environment")
          expect(File.read(workflow_path)).to include("railway environment delete")
          expect(installer.github_action_generated?).to be true
        end
      end

      context "when github_action option is disabled (default)" do
        it "does not create the workflow file" do
          installer.install!

          workflow_path = File.join(temp_dir, ".github", "workflows", "switchyard-cleanup-pr.yml")
          expect(File.exist?(workflow_path)).to be false
          expect(installer.github_action_generated?).to be false
        end
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
