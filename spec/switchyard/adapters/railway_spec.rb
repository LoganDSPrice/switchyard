# frozen_string_literal: true

require "spec_helper"
require "switchyard/adapters/railway"

RSpec.describe Switchyard::Adapters::Railway do
  subject(:adapter) { described_class.new(runner: runner) }

  let(:runner) { instance_double("Switchyard::ProcessRunner") }

  before do
    allow(runner).to receive(:capture).with("railway", "service", "list", any_args).and_return(["[]", double(success?: true)])
  end

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

    it "auto-detects the app service when no service is configured on adapter" do
      services_with_pg = '[{ "id": "srv-db", "name": "Postgres", "source": { "image": "postgres:18" } }, { "id": "srv-app", "name": "switchyard-canary", "source": { "repo": "LoganDSPrice/switchyard-canary" } }]'
      expect(runner).to receive(:capture).with(
        "railway", "service", "list", "--environment", "pr-3", "--json"
      ).and_return([services_with_pg, double(success?: true)])

      expect(runner).to receive(:exec).with(
        "railway", "logs", "--environment", "pr-3", "--service", "switchyard-canary", "--lines", "10"
      )

      adapter.logs("pr-3", "--lines", "10")
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

    let(:env_config_with_repo_json) do
      <<~JSON
        {
          "services": {
            "srv-1": {
              "source": {
                "repo": "LoganDSPrice/NBA-Over-Under-Redux",
                "branch": "main"
              }
            }
          }
        }
      JSON
    end

    let(:env_config_updated_json) do
      <<~JSON
        {
          "services": {
            "srv-1": {
              "source": {
                "repo": "LoganDSPrice/NBA-Over-Under-Redux",
                "branch": "test/preview-app-banner"
              },
              "variables": {
                "PORT": { "value": "80" }
              }
            }
          }
        }
      JSON
    end

    let(:env_config_updated_no_port_json) do
      <<~JSON
        {
          "services": {
            "srv-1": {
              "source": {
                "repo": "LoganDSPrice/NBA-Over-Under-Redux",
                "branch": "test/preview-app-banner"
              }
            }
          }
        }
      JSON
    end

    let(:env_config_without_repo_json) do
      <<~JSON
        {
          "services": {
            "srv-1": {
              "source": {}
            }
          }
        }
      JSON
    end

    let(:environments_json_linked) do
      <<~JSON
        [
          { "id": "env-1", "name": "production", "isLinked": true },
          { "id": "env-2", "name": "staging", "isLinked": false }
        ]
      JSON
    end

    before do
      allow(runner).to receive(:capture).with("railway", "deployment", "list", any_args).and_return(["[]", double(success?: true)])
      allow(adapter).to receive(:pause)
    end

    context "when PR environment does not exist yet" do
      it "provisions environment non-interactively with --service-config, verifies source.branch and PORT, and restores the prior linked environment from environment list" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_linked, double(success?: true)])

        expect(runner).not_to receive(:capture).with("railway", "status", any_args)

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "staging", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157",
          "--duplicate", "staging",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return(
          [env_config_with_repo_json, double(success?: true)],
          [env_config_updated_json, double(success?: true)]
        )

        expect(runner).not_to receive(:capture).with("railway", "service", "source", "connect", any_args)
        expect(runner).not_to receive(:capture).with("railway", "variable", "set", any_args)
        expect(runner).not_to receive(:capture).with("railway", "environment", "edit", "--environment", "staging", any_args)
        expect(runner).not_to receive(:capture).with("railway", "environment", "edit", "--environment", "production", any_args)

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).and_return(['{"committed":true}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "link", "production", "--json"
        ).and_return(['{"name":"production"}', double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          port: 80
        )
        expect(result).to be(true)
      end

      it "skips railway environment edit when railway environment new --service-config already applied the target branch and PORT" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_linked, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "staging", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157",
          "--duplicate", "staging",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return([env_config_updated_json, double(success?: true)])

        expect(runner).not_to receive(:capture).with("railway", "environment", "edit", any_args)

        expect(runner).to receive(:capture).with(
          "railway", "environment", "link", "production", "--json"
        ).and_return(['{"name":"production"}', double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          port: 80
        )
        expect(result).to be(true)
      end

      it "waits for async environment duplication and retries edit if post-edit config still shows the base branch" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_linked, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "production", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157",
          "--duplicate", "production",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return(
          ['{"services":{}}', double(success?: true)],
          [env_config_with_repo_json, double(success?: true)],
          [env_config_with_repo_json, double(success?: true)],
          [env_config_updated_json, double(success?: true)]
        )

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).twice.and_return(
          ['{"committed":false}', double(success?: true)],
          ['{"committed":true,"staged":true}', double(success?: true)]
        )

        expect(runner).to receive(:capture).with(
          "railway", "environment", "link", "production", "--json"
        ).and_return(['{"name":"production"}', double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          base_environment: "production",
          port: 80
        )
        expect(result).to be(true)
      end

      it "raises CommandError and still restores the prior linked environment when post-edit verification never shows the PR branch" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_linked, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "staging", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157",
          "--duplicate", "staging",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        allow(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return([env_config_with_repo_json, double(success?: true)])

        allow(runner).to receive(:capture).with(
          "railway", "environment", "edit", any_args
        ).and_return(['{"committed":false}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "link", "production", "--json"
        ).and_return(['{"name":"production"}', double(success?: true)])

        expect do
          adapter.deploy_pr(
            "pr-157",
            repo: "LoganDSPrice/NBA-Over-Under-Redux",
            branch: "test/preview-app-banner",
            port: 80
          )
        end.to raise_error(Switchyard::Adapters::Railway::CommandError, /Failed to verify environment 'pr-157'/)
      end

      it "cancels in-flight duplicate deployment if one was triggered during environment creation" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "staging", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157",
          "--duplicate", "staging",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        in_flight_json = '[{ "id": "dep-old-main", "status": "BUILDING" }]'
        expect(runner).to receive(:capture).with(
          "railway", "deployment", "list",
          "--service", "srv-1",
          "--environment", "pr-157",
          "--json"
        ).and_return([in_flight_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "api", "mutation($id: String!) { deploymentCancel(id: $id) }",
          "--var", "id=dep-old-main"
        ).and_return(["Cancelled", double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return(
          [env_config_with_repo_json, double(success?: true)],
          [env_config_updated_json, double(success?: true)]
        )

        expect(runner).not_to receive(:capture).with("railway", "service", "source", "connect", any_args)

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).and_return(['{"committed":true}', double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          port: 80
        )
        expect(result).to be(true)
      end

      it "falls back to duplicating production if staging does not exist on Railway without mutating production" do
        prod_only_json = '[{ "id": "env-1", "name": "production" }]'
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([prod_only_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "production", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157",
          "--duplicate", "production",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return(
          [env_config_with_repo_json, double(success?: true)],
          [env_config_updated_json, double(success?: true)]
        )

        expect(runner).not_to receive(:capture).with("railway", "service", "source", "connect", any_args)
        expect(runner).not_to receive(:capture).with("railway", "environment", "edit", "--environment", "production", any_args)

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).and_return(['{"committed":true}', double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          port: 80
        )
        expect(result).to be(true)
      end

      it "resolves service ID from resolved base environment (production) when newly duplicated PR environment has no services yet and staging does not exist" do
        prod_only_object_json = '{"environments":[{"id":"env-1","name":"production","isLinked":true}]}'
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([prod_only_object_json, double(success?: true)])

        expect(runner).not_to receive(:capture).with(
          "railway", "service", "list", "--environment", "staging", "--json"
        )

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "production", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "new", "pr-157",
          "--duplicate", "production",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "--json"
        ).and_return(['{"name":"pr-157"}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return(
          [env_config_with_repo_json, double(success?: true)],
          [env_config_updated_json, double(success?: true)]
        )

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).and_return(['{"committed":true}', double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "link", "production", "--json"
        ).and_return(['{"name":"production"}', double(success?: true)])

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

      it "skips environment creation and updates only the PR environment via railway environment edit" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_with_pr, double(success?: true)])

        expect(runner).not_to receive(:capture).with(
          "railway", "environment", "new", any_args
        )
        expect(runner).not_to receive(:capture).with(
          "railway", "environment", "link", any_args
        )

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "pr-157", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return(
          [env_config_with_repo_json, double(success?: true)],
          [env_config_updated_json, double(success?: true)]
        )

        expect(runner).not_to receive(:capture).with("railway", "service", "source", "connect", any_args)
        expect(runner).not_to receive(:capture).with("railway", "variable", "set", any_args)

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "--service-config", "srv-1", "variables.PORT.value", "80",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).and_return(['{"committed":true}', double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          port: 80
        )
        expect(result).to be(true)
      end

      it "includes source.repo in railway environment edit when the environment does not already have source.repo connected" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_with_pr, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "pr-157", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return(
          [env_config_without_repo_json, double(success?: true)],
          [env_config_updated_no_port_json, double(success?: true)]
        )

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "srv-1", "source.repo", "LoganDSPrice/NBA-Over-Under-Redux",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).and_return(['{"committed":true}', double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner"
        )
        expect(result).to be(true)
      end

      it "resolves explicit service name to service ID from railway service list" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_with_pr, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "pr-157", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return(
          [env_config_with_repo_json, double(success?: true)],
          [env_config_updated_no_port_json, double(success?: true)]
        )

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).and_return(['{"committed":true}', double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          service: "NBA-Over-Under-Redux"
        )
        expect(result).to be(true)
      end

      it "falls back to explicit service name and passes source.repo when service list and environment config fail" do
        fallback_config_json = <<~JSON
          {
            "services": {
              "NBA-Over-Under-Redux": {
                "source": {
                  "repo": "LoganDSPrice/NBA-Over-Under-Redux",
                  "branch": "test/preview-app-banner"
                }
              }
            }
          }
        JSON

        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_with_pr, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "pr-157", "--json"
        ).and_return(["", double(success?: false)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return(
          ["", double(success?: false)],
          [fallback_config_json, double(success?: true)]
        )

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "NBA-Over-Under-Redux", "source.repo", "LoganDSPrice/NBA-Over-Under-Redux",
          "--service-config", "NBA-Over-Under-Redux", "source.branch", "test/preview-app-banner",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).and_return(['{"committed":true}', double(success?: true)])

        result = adapter.deploy_pr(
          "pr-157",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "test/preview-app-banner",
          service: "NBA-Over-Under-Redux"
        )
        expect(result).to be(true)
      end

      it "raises CommandError when railway environment edit fails" do
        expect(runner).to receive(:capture).with(
          "railway", "environment", "list", "--json"
        ).and_return([environments_json_with_pr, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "service", "list", "--environment", "pr-157", "--json"
        ).and_return([services_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "config", "--environment", "pr-157", "--json"
        ).and_return([env_config_with_repo_json, double(success?: true)])

        expect(runner).to receive(:capture).with(
          "railway", "environment", "edit",
          "--environment", "pr-157",
          "--service-config", "srv-1", "source.branch", "test/preview-app-banner",
          "-m", "Deploy PR #157 (test/preview-app-banner)",
          "--json"
        ).and_return(["Service not found", double(success?: false, exitstatus: 1)])

        expect do
          adapter.deploy_pr(
            "pr-157",
            repo: "LoganDSPrice/NBA-Over-Under-Redux",
            branch: "test/preview-app-banner"
          )
        end.to raise_error(Switchyard::Adapters::Railway::CommandError, /Failed to update environment 'pr-157'/)
      end
    end

    describe "regression guard against global source mutation" do
      it "never invokes railway service source connect or mutates base environments" do
        captured_commands = []
        edited = false
        allow(runner).to receive(:capture) do |*args|
          captured_commands << args
          case args[0..2]
          when %w[railway environment list]
            [environments_json_linked, double(success?: true)]
          when %w[railway environment new]
            ['{"name":"pr-170"}', double(success?: true)]
          when %w[railway service list]
            [services_json, double(success?: true)]
          when %w[railway deployment list]
            ["[]", double(success?: true)]
          when %w[railway environment config]
            branch_val = edited ? "feat/scoreboard-stakes-argon" : "main"
            json = <<~JSON
              {
                "services": {
                  "srv-1": {
                    "source": { "repo": "LoganDSPrice/NBA-Over-Under-Redux", "branch": "#{branch_val}" },
                    "variables": { "PORT": { "value": "80" } }
                  }
                }
              }
            JSON
            [json, double(success?: true)]
          when %w[railway environment edit]
            edited = true
            ['{"committed":true}', double(success?: true)]
          when %w[railway environment link]
            ['{"name":"production"}', double(success?: true)]
          else
            ["", double(success?: false)]
          end
        end

        adapter.deploy_pr(
          "pr-170",
          repo: "LoganDSPrice/NBA-Over-Under-Redux",
          branch: "feat/scoreboard-stakes-argon",
          base_environment: "production",
          port: 80
        )

        expect(captured_commands).not_to include(array_including("source", "connect"))
        mutating_commands = captured_commands.select do |cmd|
          [%w[railway environment edit], %w[railway variable set]].include?(cmd[0..2])
        end
        expect(mutating_commands).not_to be_empty
        mutating_commands.each do |cmd|
          expect(cmd).to include("--environment", "pr-170")
          expect(cmd).not_to include("production")
          expect(cmd).not_to include("staging")
        end
      end
    end
  end
end
