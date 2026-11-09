# frozen_string_literal: true

module Switchyard
  module Database
    class MetadataFixer
      def initialize(target_db:, environment:, runner: ProcessRunner.new)
        @target_db = target_db
        @environment = environment
        @runner = runner
      end

      def run!
        sql = <<~SQL.strip.gsub("\n", " ")
          CREATE TABLE IF NOT EXISTS public.ar_internal_metadata (
            key character varying NOT NULL,
            value character varying,
            created_at timestamp without time zone NOT NULL,
            updated_at timestamp without time zone NOT NULL,
            CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key)
          );
          INSERT INTO ar_internal_metadata (key, value, created_at, updated_at)
          VALUES ('environment', '#{environment}', NOW(), NOW())
          ON CONFLICT (key) DO UPDATE SET value = '#{environment}', updated_at = NOW();
        SQL

        runner.system(%(psql #{target_db} -c "#{sql}"))
      end

      private

      attr_reader :target_db, :environment, :runner
    end
  end
end
