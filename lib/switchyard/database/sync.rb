# frozen_string_literal: true

require_relative "metadata_fixer"
require_relative "../process_runner"

module Switchyard
  module Database
    class Sync
      class ProtectedEnvironmentError < Error; end
      class RestoreError < Error; end

      PROTECTED_ENVIRONMENTS = %w[production main].freeze

      def initialize(source_url:, target_db: nil, target_url: nil, target_env: "development", runner: ProcessRunner.new, force: false)
        @source_url = source_url
        @target_db = target_db
        @target_url = target_url
        @target_env = target_env.to_s
        @runner = runner
        @force = force
      end

      def run!
        validate_environment_safety!

        recreate_target_database! unless target_url
        stream_database!
        update_metadata!

        true
      end

      private

      attr_reader :source_url, :target_db, :target_url, :target_env, :runner, :force

      def validate_environment_safety!
        return unless PROTECTED_ENVIRONMENTS.include?(target_env)
        return if force

        raise ProtectedEnvironmentError,
              "Restoring into '#{target_env}' is blocked for safety. Use --force to override."
      end

      def recreate_target_database!
        return unless target_db

        success = runner.system("dropdb --if-exists #{target_db} && createdb #{target_db}")
        raise RestoreError, "Failed to recreate local database #{target_db}" unless success
      end

      def stream_database!
        dump_cmd = pg_binary("pg_dump")
        restore_cmd = pg_binary("pg_restore")

        cmd = if target_url
                %(#{dump_cmd} --no-acl --no-owner -Fc "#{source_url}" | #{restore_cmd} --clean --if-exists --no-acl --no-owner -d "#{target_url}")
              else
                %(#{dump_cmd} --no-acl --no-owner --clean --if-exists -Fc "#{source_url}" | #{restore_cmd} --no-acl --no-owner --dbname=#{target_db} --verbose)
              end

        success = runner.system(cmd)
        raise RestoreError, "pg_dump | pg_restore pipeline failed" unless success
      end

      def update_metadata!
        target_destination = target_url ? %("#{target_url}") : target_db
        MetadataFixer.new(target_db: target_destination, environment: target_env, runner: runner).run!
      end

      def pg_binary(name)
        postgres_app_bin = "/Applications/Postgres.app/Contents/Versions/latest/bin/#{name}"
        return postgres_app_bin if File.executable?(postgres_app_bin)

        name
      end
    end
  end
end
