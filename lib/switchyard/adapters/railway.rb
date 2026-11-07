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

      def deploy_pr(environment, repo:, branch:, service: nil, base_environment: "staging")
        ensure_environment_exists!(environment, duplicate_from: base_environment)
        resolved_service = service || find_app_service(repo)

        cmd = [
          "railway", "service", "source", "connect",
          "--environment", environment.to_s,
          "--repo", repo.to_s,
          "--branch", branch.to_s
        ]
        cmd += ["--service", resolved_service.to_s] if resolved_service

        stdout, status = runner.capture(*cmd)
        unless status&.success?
          raise CommandError, "Failed to connect service source on Railway: #{stdout.strip}"
        end

        true
      end

      private

      def ensure_environment_exists!(environment, duplicate_from:)
        stdout, status = runner.capture("railway", "environment", "list", "--json")
        environments = []
        if status&.success? && (json_str = stdout[/\[.*\]/m])
          parsed = begin
            JSON.parse(json_str)
          rescue StandardError
            []
          end
          environments = parsed.map { |e| e["name"] }
        end

        return if environments.include?(environment.to_s)

        success = runner.system("railway", "environment", "new", environment.to_s, "--duplicate", duplicate_from.to_s)
        unless success
          raise CommandError, "Failed to create Railway environment '#{environment}' duplicating '#{duplicate_from}'"
        end
      end

      def find_app_service(target_repo = nil)
        stdout, status = runner.capture("railway", "service", "list", "--json")
        return unless status&.success?

        json_str = stdout[/\[.*\]/m]
        return unless json_str

        services = begin
          JSON.parse(json_str)
        rescue StandardError
          []
        end
        matching = services.find { |s| s.dig("source", "repo") == target_repo } if target_repo
        matching ||= services.find { |s| s.dig("source", "repo") }
        matching ||= services.find { |s| s["name"] !~ /postgres|redis|mysql|db/i }
        matching ||= services.first

        matching&.dig("name")
      rescue StandardError
        nil
      end
    end
  end
end
