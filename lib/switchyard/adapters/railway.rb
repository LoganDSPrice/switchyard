# frozen_string_literal: true

require "json"
require_relative "base"

module Switchyard
  module Adapters
    class Railway < Base
      class CommandError < Error; end
      class VariableNotFoundError < Error; end

      DATABASE_KEYS = %w[DATABASE_PUBLIC_URL DATABASE_URL].freeze

      def console(environment, *args)
        runner.exec("railway", "ssh", "--environment", environment.to_s, "--", "bin/rails", "console", *args)
      end

      def logs(environment, *args)
        runner.exec("railway", "logs", "--environment", environment.to_s, *args)
      end

      def migrate(environment, *args)
        runner.system("railway", "ssh", "--environment", environment.to_s, "--", "bin/rails", "db:migrate", *args)
      end

      def database_url(environment)
        stdout, status = runner.capture("railway", "variables", "--environment", environment.to_s, "--json")

        unless status.success?
          raise CommandError, "Failed to fetch variables for environment '#{environment}': #{stdout.strip}"
        end

        parsed = JSON.parse(stdout)
        url_key = DATABASE_KEYS.find { |key| parsed.key?(key) && !parsed[key].to_s.empty? }

        url_key ? parsed[url_key] : raise(VariableNotFoundError, "Neither DATABASE_PUBLIC_URL nor DATABASE_URL found in environment '#{environment}'")
      end

      def resolve_pr_environment(identifier)
        clean = identifier.to_s.sub(/\Apr-?/i, "")
        "pr-#{clean}"
      end
    end
  end
end
