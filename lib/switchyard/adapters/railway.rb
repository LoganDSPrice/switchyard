# frozen_string_literal: true

require "json"
require_relative "base"

module Switchyard
  module Adapters
    class Railway < Base
      class CommandError < Error; end
      class VariableNotFoundError < Error; end

      DATABASE_KEY = "DATABASE_URL"

      def console(environment, *args)
        runner.exec("railway", "run", "--environment", environment.to_s, "bin/rails", "console", *args)
      end

      def logs(environment, *args)
        runner.exec("railway", "logs", "--environment", environment.to_s, *args)
      end

      def migrate(environment, *args)
        runner.system("railway", "run", "--environment", environment.to_s, "bin/rails", "db:migrate", *args)
      end

      def database_url(environment)
        stdout, status = runner.capture("railway", "variables", "--environment", environment.to_s, "--json")

        unless status.success?
          raise CommandError, "Failed to fetch variables for environment '#{environment}': #{stdout.strip}"
        end

        parsed = JSON.parse(stdout)
        parsed.fetch(DATABASE_KEY) do
          raise VariableNotFoundError, "#{DATABASE_KEY} not found in environment '#{environment}'"
        end
      end

      def resolve_pr_environment(identifier)
        clean = identifier.to_s.sub(/\Apr-?/i, "")
        "pr-#{clean}"
      end
    end
  end
end
