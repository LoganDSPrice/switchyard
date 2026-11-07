# frozen_string_literal: true

require "spec_helper"
require "switchyard/adapters/railway"

RSpec.describe Switchyard::Adapters::Railway do
  subject(:adapter) { described_class.new(runner: runner) }

  let(:runner) { instance_double("Switchyard::ProcessRunner") }

  describe "#console" do
    it "executes rails console remotely inside the container via ssh" do
      expect(runner).to receive(:exec).with(
        "railway", "ssh", "--environment", "staging", "--", "bin/rails", "console"
      )

      adapter.console("staging")
    end

    it "passes additional flags to console" do
      expect(runner).to receive(:exec).with(
        "railway", "ssh", "--environment", "production", "--", "bin/rails", "console", "--sandbox"
      )

      adapter.console("production", "--sandbox")
    end
  end

  describe "#logs" do
    it "invokes railway logs for the environment" do
      expect(runner).to receive(:exec).with(
        "railway", "logs", "--environment", "staging"
      )

      adapter.logs("staging")
    end
  end

  describe "#migrate" do
    it "executes db:migrate remotely inside the container via ssh" do
      expect(runner).to receive(:system).with(
        "railway", "ssh", "--environment", "staging", "--", "bin/rails", "db:migrate"
      ).and_return(true)

      expect(adapter.migrate("staging")).to be(true)
    end
  end

  describe "#database_url" do
    let(:json_output) do
      <<~JSON
        {
          "DATABASE_URL": "postgresql://postgres:secret@monorail.proxy.rlwy.net:12345/railway",
          "PORT": "3000"
        }
      JSON
    end

    it "fetches variables in JSON and returns DATABASE_URL" do
      expect(runner).to receive(:capture).with(
        "railway", "variables", "--environment", "staging", "--json"
      ).and_return([json_output, double(success?: true)])

      expect(adapter.database_url("staging")).to eq(
        "postgresql://postgres:secret@monorail.proxy.rlwy.net:12345/railway"
      )
    end

    it "prefers DATABASE_PUBLIC_URL when available for external access" do
      json = '{"DATABASE_URL": "postgresql://postgres:secret@postgres.railway.internal:5432/railway", "DATABASE_PUBLIC_URL": "postgresql://postgres:secret@proxy.rlwy.net:123/railway"}'
      expect(runner).to receive(:capture).with(
        "railway", "variables", "--environment", "staging", "--json"
      ).and_return([json, double(success?: true)])

      expect(adapter.database_url("staging")).to eq(
        "postgresql://postgres:secret@proxy.rlwy.net:123/railway"
      )
    end

    it "raises an error if DATABASE_URL is not found" do
      expect(runner).to receive(:capture).with(
        "railway", "variables", "--environment", "staging", "--json"
      ).and_return(['{"PORT": "3000"}', double(success?: true)])

      expect {
        adapter.database_url("staging")
      }.to raise_error(Switchyard::Adapters::Railway::VariableNotFoundError, /DATABASE_URL.*found/)
    end

    it "raises an error if railway CLI fails" do
      expect(runner).to receive(:capture).with(
        "railway", "variables", "--environment", "staging", "--json"
      ).and_return(["Project not found", double(success?: false, exitstatus: 1)])

      expect {
        adapter.database_url("staging")
      }.to raise_error(Switchyard::Adapters::Railway::CommandError, /Failed to fetch variables/)
    end
  end

  describe "#resolve_pr_environment" do
    it "formats PR numbers into railway environment names" do
      expect(adapter.resolve_pr_environment("142")).to eq("pr-142")
      expect(adapter.resolve_pr_environment(142)).to eq("pr-142")
    end
  end

  describe "#deploy_pr" do
    let(:environments_json) do
      <<~JSON
        [
          { "id": "env-1", "name": "production" },
          { "id": "env-2", "name": "staging" }
        ]
      JSON
    end

    let(:services_json) do
      <<~JSON
        [
          {
            "id": "srv-1",
            "name": "NBA-Over-Under-Redux",
            "source": { "repo": "LoganDSPrice/NBA-Over-Under-Redux" }
          },
          {
            "id": "srv-2",
            "name": "Postgres",
            "source": { "repo": null, "image": "postgres:17" }
          }
        ]
      JSON
    end

    context "when PR environment does not exist yet" do
      it "provisions environment by duplicating staging and connects the service to the GitHub branch" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json, double(success?: true)])

        expect(runner).to receive(:system).with(
          "railway", "environment", "new", "pr-157", "--duplicate", "staging"
        ).and_return(true)

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "source", "connect",
          "--environment", "pr-157",
          "--repo", "LoganDSPrice/NBA-Over-Under-Redux",
          "--branch", "test/preview-app-banner",
          "--service", "NBA-Over-Under-Redux"
        ).and_return(["Connected source", double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner"
        )
        expect(result).to be(true)
      end

      it "falls back to duplicating production if staging does not exist on Railway" do
        prod_only_json = '[{ "id": "env-1", "name": "production" }]'
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([prod_only_json, double(success?: true)])

        expect(runner).to receive(:system).with(
          "railway", "environment", "new", "pr-157", "--duplicate", "production"
        ).and_return(true)

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "source", "connect",
          "--environment", "pr-157",
          "--repo", "LoganDSPrice/NBA-Over-Under-Redux",
          "--branch", "test/preview-app-banner",
          "--service", "NBA-Over-Under-Redux"
        ).and_return(["Connected source", double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner"
        )
        expect(result).to be(true)
      end
    end

    context "when PR environment already exists" do
      let(:environments_json_with_pr) do
        <<~JSON
          [
            { "id": "env-1", "name": "production" },
            { "id": "env-2", "name": "staging" },
            { "id": "env-3", "name": "pr-157" }
          ]
        JSON
      end

      it "skips environment creation and connects the service to GitHub" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_with_pr, double(success?: true)])

        expect(runner).not_to receive(:system).with(
          "railway", "environment", "new", any_args
        )

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "source", "connect",
          "--environment", "pr-157",
          "--repo", "LoganDSPrice/NBA-Over-Under-Redux",
          "--branch", "test/preview-app-banner",
          "--service", "NBA-Over-Under-Redux"
        ).and_return(["Connected source", double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner"
        )
        expect(result).to be(true)
      end
    end
  end
end
