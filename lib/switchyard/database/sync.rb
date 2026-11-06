# frozen_string_literal: true

require_relative "metadata_fixer"
require_relative "../process_runner"

module Switchyard
  module Database
    class Sync
      class ProtectedEnvironmentError < Error; end
      class RestoreError < Error; end

      PROTECTED_ENVIRONMENTS = %w[production main].freeze

      def initialize(source_url:, target_db:, target_env: "development", runner: ProcessRunner.new, force: false)
        @source_url = source_url
        @target_db = target_db
        @target_env = target_env.to_s
        @runner = runner
        @force = force
      end

      def run!
        validate_environment_safety!

        recreate_target_database!
        stream_database!
        update_metadata!

        true
      end

      private

      attr_reader :source_url, :target_db, :target_env, :runner, :force

      def validate_environment_safety!
        return unless PROTECTED_ENVIRONMENTS.include?(target_env)
        return if force

        raise ProtectedEnvironmentError,
              "Restoring into '#{target_env}' is blocked for safety. Use --force to override."
      end

      def recreate_target_database!
        success = runner.system("dropdb --if-exists #{target_db} && createdb #{target_db}")
        raise RestoreError, "Failed to recreate local database #{target_db}" unless success
      end

      def stream_database!
        # Pipe pg_dump straight into pg_restore with zero disk usage
        cmd = %(pg_dump --no-acl --no-owner --clean --if-exists -Fc "#{source_url}" | pg_restore --no-acl --no-owner --dbname=#{target_db} --verbose)
        success = runner.system(cmd)
        raise RestoreError, "pg_dump | pg_restore pipeline failed" unless success
      end

      def update_metadata!
        MetadataFixer.new(target_db: target_db, environment: target_env, runner: runner).run!
      end
    end
  end
end
