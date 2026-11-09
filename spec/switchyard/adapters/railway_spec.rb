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

    it "includes --service when service is configured on adapter" do
      adapter_with_service = described_class.new(runner: runner, service: "NBA-Over-Under-Redux")
      expect(runner).to receive(:exec).with(
        "railway", "ssh", "--environment", "staging", "--service", "NBA-Over-Under-Redux", "--", "bin/rails", "console"
      )

      adapter_with_service.console("staging")
    end
  end

  describe "#logs" do
    it "invokes railway logs for the environment" do
      expect(runner).to receive(:exec).with(
        "railway", "logs", "--environment", "staging"
      )

      adapter.logs("staging")
    end

    it "includes --service when service is configured on adapter" do
      adapter_with_service = described_class.new(runner: runner, service: "NBA-Over-Under-Redux")
      expect(runner).to receive(:exec).with(
        "railway", "logs", "--environment", "staging", "--service", "NBA-Over-Under-Redux"
      )

      adapter_with_service.logs("staging")
    end
  end

  describe "#migrate" do
    it "executes db:migrate remotely inside the container via ssh" do
      expect(runner).to receive(:system).with(
        "railway", "ssh", "--environment", "staging", "--", "bin/rails", "db:migrate"
      ).and_return(true)

      expect(adapter.migrate("staging")).to be(true)
    end

    it "includes --service when service is configured on adapter" do
      adapter_with_service = described_class.new(runner: runner, service: "NBA-Over-Under-Redux")
      expect(runner).to receive(:system).with(
        "railway", "ssh", "--environment", "staging", "--service", "NBA-Over-Under-Redux", "--", "bin/rails", "db:migrate"
      ).and_return(true)

      expect(adapter_with_service.migrate("staging")).to be(true)
    end
  end

  describe "#seed" do
    it "executes db:seed remotely inside the container via ssh" do
      expect(runner).to receive(:system).with(
        "railway", "ssh", "--environment", "pr-157", "--", "bin/rails", "db:seed"
      ).and_return(true)

      expect(adapter.seed("pr-157")).to be(true)
    end

    it "includes --service when service is configured on adapter" do
      adapter_with_service = described_class.new(runner: runner, service: "NBA-Over-Under-Redux")
      expect(runner).to receive(:system).with(
        "railway", "ssh", "--environment", "pr-157", "--service", "NBA-Over-Under-Redux", "--", "bin/rails", "db:seed"
      ).and_return(true)

      expect(adapter_with_service.seed("pr-157")).to be(true)
    end
  end

  describe "#resolve_base_environment" do
    it "returns staging when staging exists" do
      json = '[{ "name": "production" }, { "name": "staging" }]'
      expect(runner).to receive(:capture).with("railway", "environment", "list", "--json")
                                         .and_return([json, double(success?: true)])

      expect(adapter.resolve_base_environment).to eq("staging")
    end

    it "falls back to production when staging does not exist" do
      json = '[{ "name": "production" }]'
      expect(runner).to receive(:capture).with("railway", "environment", "list", "--json")
                                         .and_return([json, double(success?: true)])

      expect(adapter.resolve_base_environment).to eq("production")
    end
  end

  describe "#database_url" do
    before do
      allow(runner).to receive(:capture).with("railway", "service", "list", any_args).and_return(["[]", double(success?: true)])
    end

    let(:json_output) do
      <<~JSON
        {
          "DATABASE_URL": "postgresql://postgres:secret@monorail.proxy.rlwy.net:12345/railway",
          "PORT": "3000"
        }
      JSON
    end

    it "queries the database service when auto-detected" do
      services_with_pg = '[{ "name": "NBA-Over-Under-Redux" }, { "name": "Postgres", "source": { "image": "postgres:17" } }]'
      expect(runner).to receive(:capture).with(
        "railway", "service", "list", "--environment", "staging", "--json"
      ).and_return([services_with_pg, double(success?: true)])

      expect(runner).to receive(:capture).with(
        "railway", "variables", "--environment", "staging", "--service", "Postgres", "--json"
      ).and_return([json_output, double(success?: true)])

      expect(adapter.database_url("staging")).to eq(
        "postgresql://postgres:secret@monorail.proxy.rlwy.net:12345/railway"
      )
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

      expect do
        adapter.database_url("staging")
      end.to raise_error(Switchyard::Adapters::Railway::VariableNotFoundError, /DATABASE_URL.*found/)
    end

    it "raises an error if railway CLI fails" do
      expect(runner).to receive(:capture).with(
        "railway", "variables", "--environment", "staging", "--json"
      ).and_return(["Project not found", double(success?: false, exitstatus: 1)])

      expect do
        adapter.database_url("staging")
      end.to raise_error(Switchyard::Adapters::Railway::CommandError, /Failed to fetch variables/)
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

    before do
      allow(runner).to receive(:capture).with("railway", "deployment", "list", any_args).and_return(["[]", double(success?: true)])
    end

    context "when PR environment does not exist yet" do
      it "provisions environment non-interactively with --json duplicating staging and connects the service to the GitHub branch" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157", "--duplicate", "staging", "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "pr-157", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "variable", "set", "PORT=80",
          "--environment", "pr-157",
          "--service", "NBA-Over-Under-Redux"
        ).and_return(["Set PORT=80", double(success?: true)])

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
          branch: "test/preview-app-banner",
          port: 80
        )
        expect(result).to be(true)
      end

      it "cancels in-flight duplicate deployment if one was triggered during environment creation" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157", "--duplicate", "staging", "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "pr-157", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "variable", "set", "PORT=80",
          "--environment", "pr-157",
          "--service", "NBA-Over-Under-Redux"
        ).and_return(["Set PORT=80", double(success?: true)])

        in_flight_json = '[{ "id": "dep-old-main", "status": "BUILDING" }]'
        expect(runner).to receive(:capture).with(
          "railway", "deployment", "list",
          "--service", "NBA-Over-Under-Redux",
          "--environment", "pr-157",
          "--json"
        ).and_return([in_flight_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "api", "mutation($id: String!) { deploymentCancel(id: $id) }",
          "--var", "id=dep-old-main"
        ).and_return(["Cancelled", double(success?: true)])

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
          branch: "test/preview-app-banner",
          port: 80
        )
        expect(result).to be(true)
      end

      it "falls back to duplicating production if staging does not exist on Railway" do
        prod_only_json = '[{ "id": "env-1", "name": "production" }]'
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([prod_only_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157", "--duplicate", "production", "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "pr-157", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "variable", "set", "PORT=80",
          "--environment", "pr-157",
          "--service", "NBA-Over-Under-Redux"
        ).and_return(["Set PORT=80", double(success?: true)])

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
          branch: "test/preview-app-banner",
          port: 80
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

        expect(runner).not_to receive(:capture).with(
          "railway", "environment", "new", any_args
        )

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "pr-157", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "variable", "set", "PORT=80",
          "--environment", "pr-157",
          "--service", "NBA-Over-Under-Redux"
        ).and_return(["Set PORT=80", double(success?: true)])

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
          branch: "test/preview-app-banner",
          port: 80
        )
        expect(result).to be(true)
      end
    end
  end
end
