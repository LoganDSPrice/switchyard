# frozen_string_literal: true

require "spec_helper"
require "switchyard/adapters/railway"

RSpec.describe Switchyard::Adapters::Railway do
  subject(:adapter) { described_class.new(runner: runner) }

  let(:runner) { instance_double("Switchyard::ProcessRunner") }

  describe "#console" do
    it "executes rails console on the target environment" do
      expect(runner).to receive(:exec).with(
        "railway", "run", "--environment", "staging", "bin/rails", "console"
      )

      adapter.console("staging")
    end

    it "passes additional flags to console" do
      expect(runner).to receive(:exec).with(
        "railway", "run", "--environment", "production", "bin/rails", "console", "--sandbox"
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
    it "executes db:migrate on the environment" do
      expect(runner).to receive(:system).with(
        "railway", "run", "--environment", "staging", "bin/rails", "db:migrate"
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

    it "raises an error if DATABASE_URL is not found" do
      expect(runner).to receive(:capture).with(
        "railway", "variables", "--environment", "staging", "--json"
      ).and_return(['{"PORT": "3000"}', double(success?: true)])

      expect {
        adapter.database_url("staging")
      }.to raise_error(Switchyard::Adapters::Railway::VariableNotFoundError, /DATABASE_URL not found/)
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
end
