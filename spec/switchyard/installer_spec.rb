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

    describe "#github_secrets_url" do
      context "with an SSH GitHub remote" do
        it "returns the direct URL to add actions secrets" do
          expect(runner).to receive(:capture).with(
            "git", "remote", "get-url", "origin"
          ).and_return(["git@github.com:LoganDSPrice/NBA-Over-Under-Redux.git\n", double(success?: true)])

          expect(installer.github_secrets_url).to eq(
            "https://github.com/LoganDSPrice/NBA-Over-Under-Redux/settings/secrets/actions"
          )
        end
      end

      context "with an HTTPS GitHub remote" do
        it "returns the direct URL to add actions secrets" do
          expect(runner).to receive(:capture).with(
            "git", "remote", "get-url", "origin"
          ).and_return(["https://github.com/LoganDSPrice/NBA-Over-Under-Redux.git\n", double(success?: true)])

          expect(installer.github_secrets_url).to eq(
            "https://github.com/LoganDSPrice/NBA-Over-Under-Redux/settings/secrets/actions"
          )
        end
      end

      context "when remote is not GitHub" do
        it "returns nil" do
          expect(runner).to receive(:capture).with(
            "git", "remote", "get-url", "origin"
          ).and_return(["git@gitlab.com:user/project.git\n", double(success?: true)])

          expect(installer.github_secrets_url).to be_nil
        end
      end

      context "when git command fails" do
        it "returns nil" do
          expect(runner).to receive(:capture).with(
            "git", "remote", "get-url", "origin"
          ).and_return(["fatal: not a git repository", double(success?: false)])

          expect(installer.github_secrets_url).to be_nil
        end
      end
    end

    describe "#railway_tokens_url" do
      context "when railway status returns project and environment IDs" do
        let(:json_output) do
          <<~JSON
            {
              "project": { "id": "proj-123", "name": "MyApp" },
              "environment": { "id": "env-456", "name": "production" }
            }
          JSON
        end

        it "returns the direct tokens URL with environmentId" do
          expect(runner).to receive(:capture).with(
            "railway", "status", "--json"
          ).and_return([json_output, double(success?: true)])

          expect(installer.railway_tokens_url).to eq(
            "https://railway.com/project/proj-123/settings/tokens?environmentId=env-456"
          )
        end
      end

      context "when railway status returns standard root project schema with environments edges" do
        let(:json_output) do
          <<~JSON
            {
              "id": "e6cef8da-25b2-4aaa-a7cb-22406df4eeb6",
              "name": "OverUnder",
              "environments": {
                "edges": [
                  {
                    "node": {
                      "id": "6d8b8757-d8dd-4346-87e2-f373e05dbfc3",
                      "name": "production"
                    }
                  }
                ]
              }
            }
          JSON
        end

        it "extracts project id and production environment id from edges" do
          expect(runner).to receive(:capture).with(
            "railway", "status", "--json"
          ).and_return([json_output, double(success?: true)])

          expect(installer.railway_tokens_url).to eq(
            "https://railway.com/project/e6cef8da-25b2-4aaa-a7cb-22406df4eeb6/settings/tokens?environmentId=6d8b8757-d8dd-4346-87e2-f373e05dbfc3"
          )
        end

        it "extracts JSON cleanly even when CLI output contains update banners or warnings" do
          banner_output = "New version available: v5.71.0 visit https://docs.railway.com\n#{json_output}\nTip: Run update"
          expect(runner).to receive(:capture).with(
            "railway", "status", "--json"
          ).and_return([banner_output, double(success?: true)])

          expect(installer.railway_tokens_url).to eq(
            "https://railway.com/project/e6cef8da-25b2-4aaa-a7cb-22406df4eeb6/settings/tokens?environmentId=6d8b8757-d8dd-4346-87e2-f373e05dbfc3"
          )
        end
      end

      context "when railway status returns project ID without environment ID" do
        let(:json_output) do
          <<~JSON
            {
              "project": { "id": "proj-123", "name": "MyApp" }
            }
          JSON
        end

        it "returns the direct tokens URL without environmentId" do
          expect(runner).to receive(:capture).with(
            "railway", "status", "--json"
          ).and_return([json_output, double(success?: true)])

          expect(installer.railway_tokens_url).to eq(
            "https://railway.com/project/proj-123/settings/tokens"
          )
        end
      end

      context "when railway CLI command fails or project is unlinked" do
        it "returns nil" do
          expect(runner).to receive(:capture).with(
            "railway", "status", "--json"
          ).and_return(["Project not found", double(success?: false)])

          expect(installer.railway_tokens_url).to be_nil
        end
      end

      context "when railway CLI returns invalid JSON" do
        it "returns nil" do
          expect(runner).to receive(:capture).with(
            "railway", "status", "--json"
          ).and_return(["not json", double(success?: true)])

          expect(installer.railway_tokens_url).to be_nil
        end
      end
    end

    context "when destination is not a Rails directory" do
      it "raises a NotInRailsProjectError" do
        expect do
          installer.install!
        end.to raise_error(Switchyard::Installer::NotInRailsProjectError, /Rails project/i)
      end
    end
  end
end
