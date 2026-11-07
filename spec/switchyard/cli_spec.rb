# frozen_string_literal: true

require "spec_helper"
require "switchyard/cli"

RSpec.describe Switchyard::CLI do
  subject(:cli) { described_class.new([], {}, config) }

  let(:config) { { adapter: adapter, db_config: db_config } }
  let(:adapter) { instance_double("Switchyard::Adapters::Railway") }
  let(:db_config) { instance_double("Switchyard::DatabaseConfig") }

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
      installer_double = instance_double("Switchyard::Installer", install!: true, git_safe_enabled?: false, github_action_generated?: true)
      expect(Switchyard::Installer).to receive(:new).with(destination: Dir.pwd, git_safe: false, github_action: true).and_return(installer_double)

      described_class.start(["install", "--github-action"], config)
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

    def capture_stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original_stdout
    end
  end
end
