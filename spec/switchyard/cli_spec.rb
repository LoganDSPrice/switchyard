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
    it "invokes the installer" do
      installer_double = instance_double("Switchyard::Installer", install!: true)
      expect(Switchyard::Installer).to receive(:new).and_return(installer_double)

      described_class.start(["install"], config)
    end
  end
end
