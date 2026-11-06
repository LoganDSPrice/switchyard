# frozen_string_literal: true

require "spec_helper"
require "switchyard/database/sync"

RSpec.describe Switchyard::Database::Sync do
  subject(:sync) do
    described_class.new(
      source_url: source_url,
      target_db: target_db,
      target_env: target_env,
      runner: runner,
      force: force
    )
  end

  let(:source_url) { "postgresql://user:pass@host:5432/remote_db" }
  let(:target_db) { "myapp_development" }
  let(:target_env) { "development" }
  let(:runner) { instance_double("Switchyard::ProcessRunner") }
  let(:force) { false }

  describe "#run!" do
    context "when restoring to development" do
      it "drops/creates the database, streams pg_dump into pg_restore, and updates ar_internal_metadata" do
        expect(runner).to receive(:system).with(
          "dropdb --if-exists myapp_development && createdb myapp_development"
        ).and_return(true)

        expect(runner).to receive(:system).with(
          satisfy { |cmd| cmd.include?("pg_dump") && cmd.include?("pg_restore") && cmd.include?("myapp_development") }
        ).and_return(true)

        expect(runner).to receive(:system).with(
          satisfy { |cmd| cmd.include?("psql myapp_development") && cmd.include?("ar_internal_metadata") }
        ).and_return(true)

        expect(sync.run!).to be(true)
      end
    end

    context "when attempting to restore into a protected environment (production)" do
      let(:target_env) { "production" }

      it "raises ProtectedEnvironmentError when force is false" do
        expect {
          sync.run!
        }.to raise_error(Switchyard::Database::Sync::ProtectedEnvironmentError, /Restoring into 'production' is blocked/)
      end

      context "when force is true" do
        let(:force) { true }

        it "proceeds with the restore" do
          allow(runner).to receive(:system).and_return(true)

          expect(sync.run!).to be(true)
        end
      end
    end
  end
end
