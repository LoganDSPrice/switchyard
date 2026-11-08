# frozen_string_literal: true

require "spec_helper"
require "switchyard/cli"

RSpec.describe Switchyard::CLI do
  subject(:cli) { described_class.new([], {}, config) }

  let(:config) { { adapter: adapter, db_config: db_config, github: github, switchyard_config: switchyard_config } }
  let(:adapter) { instance_double("Switchyard::Adapters::Railway") }
  let(:db_config) { instance_double("Switchyard::DatabaseConfig") }
  let(:github) { instance_double("Switchyard::GitHub") }
  let(:switchyard_config) { instance_double("Switchyard::Config", pr_database_strategy: "copy", pr_default_db_source: "auto", app_service: nil) }

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  describe "#console" do
    it "delegates to the adapter" do
      expect(adapter).to receive(:console).with("staging")

      described_class.start(["console", "staging"], config)
    end
  end

  describe "#logs" do
    it "delegates to the adapter" do
      expect(adapter).to receive(:logs).with("production")

      described_class.start(["logs", "production"], config)
    end
  end

  describe "#migrate" do
    it "delegates to the adapter" do
      expect(adapter).to receive(:migrate).with("staging")

      described_class.start(["migrate", "staging"], config)
    end
  end

  describe "#restore" do
    it "fetches the database URL and invokes sync to development" do
      expect(adapter).to receive(:database_url).with("staging").and_return("postgresql://user:pass@host/remote")
      expect(db_config).to receive(:database_name).with("development").and_return("myapp_development")

      sync_double = instance_double("Switchyard::Database::Sync", run!: true)
      expect(Switchyard::Database::Sync).to receive(:new).with(
        source_url: "postgresql://user:pass@host/remote",
        target_db: "myapp_development",
        target_env: "development",
        force: false
      ).and_return(sync_double)

      described_class.start(["restore", "staging"], config)
    end
  end

  describe "#pr" do
    before do
      allow(adapter).to receive(:resolve_pr_environment).with("123").and_return("pr-123")
    end

    it "runs console on the resolved pr environment by default" do
      expect(adapter).to receive(:console).with("pr-123")

      described_class.start(["pr", "123", "console"], config)
    end

    it "runs logs on the resolved pr environment" do
      expect(adapter).to receive(:logs).with("pr-123")

      described_class.start(["pr", "123", "logs"], config)
    end

    it "runs migrate on the resolved pr environment" do
      expect(adapter).to receive(:migrate).with("pr-123")

      described_class.start(["pr", "123", "migrate"], config)
    end

    describe "interactive PR selection" do
      let(:selected_pr) do
        { number: 157, title: "test PR", branch: "test/preview-app-banner" }
      end

      it "interactively selects PR when no number is passed to console" do
        expect(github).to receive(:select_pr).and_return(selected_pr)
        expect(adapter).to receive(:resolve_pr_environment).with(157).and_return("pr-157")
        expect(adapter).to receive(:console).with("pr-157")

        described_class.start(["pr", "console"], config)
      end

      it "defaults to console on selected PR when pr is called with no arguments" do
        expect(github).to receive(:select_pr).and_return(selected_pr)
        expect(adapter).to receive(:resolve_pr_environment).with(157).and_return("pr-157")
        expect(adapter).to receive(:console).with("pr-157")

        described_class.start(["pr"], config)
      end

      it "lists open PRs when called as 'pr list'" do
        expect(github).to receive(:list_prs).and_return([selected_pr])

        output = capture_stdout do
          described_class.start(["pr", "list"], config)
        end

        expect(output).to include("#157 - test PR")
      end
    end

    describe "deploy subcommand" do
      let(:pr_payload) do
        {
          number: 157,
          branch: "test/preview-app-banner",
          repo: "LoganDSPrice/NBA-Over-Under-Redux"
        }
      end

      it "deploys from GitHub and copies database by default from resolved base environment" do
        expect(github).to receive(:pr_info).with("157").and_return(pr_payload)
        expect(adapter).to receive(:resolve_pr_environment).with(157).and_return("pr-157")
        expect(adapter).to receive(:deploy_pr).with(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          service: nil
        )

        expect(adapter).to receive(:resolve_base_environment).and_return("staging")
        expect(adapter).to receive(:database_url).with("staging").and_return("postgresql://user:pass@host/remote")
        expect(db_config).to receive(:database_name).with("pr-157").and_return("myapp_pr_157")
        sync_double = instance_double("Switchyard::Database::Sync", run!: true)
        expect(Switchyard::Database::Sync).to receive(:new).with(
          source_url: "postgresql://user:pass@host/remote",
          target_db: "myapp_pr_157",
          target_env: "pr-157",
          force: false
        ).and_return(sync_double)

        output = capture_stdout do
          described_class.start(["pr", "157", "deploy"], config)
        end

        expect(output).to include("Deploying PR #157 (test/preview-app-banner) to pr-157 on Railway from GitHub...")
        expect(output).to include("Connected and triggered deployment on Railway!")
        expect(output).to include("Copying database from staging into pr-157...")
      end

      it "auto-detects PR details from GitHub when called as 'pr deploy'" do
        expect(github).to receive(:select_pr).and_return(pr_payload)
        expect(github).to receive(:pr_info).with(157).and_return(pr_payload)
        expect(adapter).to receive(:resolve_pr_environment).with(157).and_return("pr-157")
        expect(adapter).to receive(:deploy_pr).with(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          service: nil
        )

        expect(adapter).to receive(:resolve_base_environment).and_return("production")
        expect(adapter).to receive(:database_url).with("production").and_return("postgresql://user:pass@host/remote")
        expect(db_config).to receive(:database_name).with("pr-157").and_return("myapp_pr_157")
        sync_double = instance_double("Switchyard::Database::Sync", run!: true)
        expect(Switchyard::Database::Sync).to receive(:new).with(
          source_url: "postgresql://user:pass@host/remote",
          target_db: "myapp_pr_157",
          target_env: "pr-157",
          force: false
        ).and_return(sync_double)

        output = capture_stdout do
          described_class.start(["pr", "deploy"], config)
        end

        expect(output).to include("Deploying PR #157")
        expect(output).to include("Copying database from production into pr-157...")
      end

      it "runs db:seed instead of copying when --seed flag is provided" do
        expect(github).to receive(:pr_info).with("157").and_return(pr_payload)
        expect(adapter).to receive(:resolve_pr_environment).with(157).and_return("pr-157")
        expect(adapter).to receive(:deploy_pr).with(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          service: nil
        )

        expect(adapter).to receive(:seed).with("pr-157")
        expect(Switchyard::Database::Sync).not_to receive(:new)

        output = capture_stdout do
          described_class.start(["pr", "157", "deploy", "--seed"], config)
        end

        expect(output).to include("Seeding database for pr-157 via bin/rails db:seed...")
      end

      it "skips database copying when --skip-db flag is provided" do
        expect(github).to receive(:pr_info).with("157").and_return(pr_payload)
        expect(adapter).to receive(:resolve_pr_environment).with(157).and_return("pr-157")
        expect(adapter).to receive(:deploy_pr).with(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          service: nil
        )

        expect(adapter).not_to receive(:seed)
        expect(Switchyard::Database::Sync).not_to receive(:new)

        output = capture_stdout do
          described_class.start(["pr", "157", "deploy", "--skip-db"], config)
        end

        expect(output).not_to include("Copying database")
        expect(output).not_to include("Seeding database")
      end

      it "copies from custom environment when --copy is provided" do
        expect(github).to receive(:pr_info).with("157").and_return(pr_payload)
        expect(adapter).to receive(:resolve_pr_environment).with(157).and_return("pr-157")
        expect(adapter).to receive(:deploy_pr).with(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          service: nil
        )

        expect(adapter).to receive(:database_url).with("production").and_return("postgresql://user:pass@host/remote")
        expect(db_config).to receive(:database_name).with("pr-157").and_return("myapp_pr_157")
        sync_double = instance_double("Switchyard::Database::Sync", run!: true)
        expect(Switchyard::Database::Sync).to receive(:new).with(
          source_url: "postgresql://user:pass@host/remote",
          target_db: "myapp_pr_157",
          target_env: "pr-157",
          force: false
        ).and_return(sync_double)

        output = capture_stdout do
          described_class.start(["pr", "157", "deploy", "--copy", "production"], config)
        end

        expect(output).to include("Copying database from production into pr-157...")
      end
    end
  end

  describe "#install" do
    it "invokes the installer with git_safe: false and github_action: false by default" do
      installer_double = instance_double("Switchyard::Installer", install!: true, git_safe_enabled?: false, github_action_generated?: false)
      expect(Switchyard::Installer).to receive(:new).with(destination: Dir.pwd, git_safe: false, github_action: false).and_return(installer_double)

      described_class.start(["install"], config)
    end

    it "passes git_safe: true when --git-safe flag is supplied" do
      installer_double = instance_double("Switchyard::Installer", install!: true, git_safe_enabled?: true, github_action_generated?: false)
      expect(Switchyard::Installer).to receive(:new).with(destination: Dir.pwd, git_safe: true, github_action: false).and_return(installer_double)

      described_class.start(["install", "--git-safe"], config)
    end

    it "passes github_action: true when --github-action flag is supplied" do
      installer_double = instance_double(
        "Switchyard::Installer",
        install!: true,
        git_safe_enabled?: false,
        github_action_generated?: true,
        railway_tokens_url: "https://railway.com/project/proj-123/settings/tokens?environmentId=env-456",
        github_secrets_url: "https://github.com/LoganDSPrice/NBA-Over-Under-Redux/settings/secrets/actions"
      )
      expect(Switchyard::Installer).to receive(:new).with(destination: Dir.pwd, git_safe: false, github_action: true).and_return(installer_double)

      output = capture_stdout do
        described_class.start(["install", "--github-action"], config)
      end

      expect(output).to include("https://railway.com/project/proj-123/settings/tokens?environmentId=env-456")
      expect(output).to include("https://github.com/LoganDSPrice/NBA-Over-Under-Redux/settings/secrets/actions")
      expect(output).to include("Click 'New repository secret'")
    end
  end

  describe "#help" do
    it "prints comprehensive help including binstub shortcuts and workflow examples" do
      output = capture_stdout do
        described_class.start(["help"], config)
      end

      expect(output).to include("Switchyard — Environment & Database Parity for Rails on Railway")
      expect(output).to include("BINSTUB SHORTCUTS")
      expect(output).to include("dev restore")
      expect(output).to include("staging console")
      expect(output).to include("pr <number>")
    end

    it "still provides command-specific help when a command is given" do
      output = capture_stdout do
        described_class.start(["help", "restore"], config)
      end

      expect(output).to include("restore [FROM] [TO]")
      expect(output).to include("--force")
    end

    it "includes INSTALLATION OPTIONS in the main help output" do
      output = capture_stdout do
        described_class.start(["help"], config)
      end

      expect(output).to include("INSTALLATION OPTIONS")
      expect(output).to include("--git-safe")
      expect(output).to include("--github-action")
    end

    it "routes '<command> --help' to command-specific help" do
      output = capture_stdout do
        described_class.start(["install", "--help"], config)
      end

      expect(output).to include("Usage:")
      expect(output).to match(/install/)
      expect(output).to include("--git-safe")
      expect(output).to include("--github-action")
    end

    it "routes '<command> -h' to command-specific help" do
      output = capture_stdout do
        described_class.start(["install", "-h"], config)
      end

      expect(output).to include("Usage:")
      expect(output).to match(/install/)
      expect(output).to include("--git-safe")
      expect(output).to include("--github-action")
    end
  end
end
