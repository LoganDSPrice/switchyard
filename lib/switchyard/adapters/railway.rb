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

      def seed(environment, *args)
        runner.system("railway", "ssh", "--environment", environment.to_s, "--", "bin/rails", "db:seed", *args)
      end

      def resolve_base_environment
        envs = list_environments
        return "staging" if envs.include?("staging")
        return "production" if envs.include?("production")

        envs.first || "staging"
      end

      def database_url(environment, service: nil)
        db_service = service || find_db_service(environment: environment)

        cmd = ["railway", "variables", "--environment", environment.to_s]
        cmd += ["--service", db_service.to_s] if db_service
        cmd << "--json"

        stdout, status = runner.capture(*cmd)

        unless status&.success?
          raise CommandError, "Failed to fetch variables for environment '#{environment}': #{stdout&.strip}"
        end

        json_str = stdout[/\{.*\}/m]
        unless json_str
          raise CommandError, "Failed to parse variables for environment '#{environment}': #{stdout&.strip}"
        end

        parsed = JSON.parse(json_str)
        url_key = DATABASE_KEYS.find { |key| parsed.key?(key) && !parsed[key].to_s.empty? }

        url_key ? parsed[url_key] : raise(VariableNotFoundError, "Neither DATABASE_PUBLIC_URL nor DATABASE_URL found in environment '#{environment}'")
      end

      def resolve_pr_environment(identifier)
        clean = identifier.to_s.sub(/\Apr-?/i, "")
        "pr-#{clean}"
      end

      def deploy_pr(environment, repo:, branch:, service: nil, base_environment: "staging", port: nil)
        ensure_environment_exists!(environment, duplicate_from: base_environment)
        resolved_service = service || find_app_service(repo, environment: environment, base_environment: base_environment)

        unless resolved_service
          raise CommandError, "Could not identify app service for deployment. Specify service via --service or config."
        end

        ensure_service_port!(environment, resolved_service, port: port) if port
        cancel_duplicate_deployment!(environment, resolved_service)

        cmd = [
          "railway", "service", "source", "connect",
          "--environment", environment.to_s,
          "--repo", repo.to_s,
          "--branch", branch.to_s,
          "--service", resolved_service.to_s
        ]

        stdout, status = runner.capture(*cmd)
        unless status&.success?
          raise CommandError, "Failed to connect service source on Railway: #{stdout&.strip}"
        end

        true
      end

      private

      def ensure_environment_exists!(environment, duplicate_from:)
        environments = list_environments

        return if environments.include?(environment.to_s)

        base = duplicate_from if environments.include?(duplicate_from.to_s)
        base ||= "staging" if environments.include?("staging")
        base ||= "production" if environments.include?("production")
        base ||= environments.first

        cmd = ["railway", "environment", "new", environment.to_s]
        cmd += ["--duplicate", base.to_s] if base
        cmd << "--json"

        stdout, status = runner.capture(*cmd)
        unless status&.success?
          raise CommandError, "Failed to create Railway environment '#{environment}'#{base ? " duplicating '#{base}'" : ""}: #{stdout&.strip}"
        end
      end

      def find_db_service(environment: nil)
        args = ["railway", "service", "list"]
        args += ["--environment", environment.to_s] if environment
        args << "--json"

        stdout, status = runner.capture(*args)
        return unless status&.success?

        json_str = stdout[/\[.*\]/m]
        return unless json_str

        services = begin
          JSON.parse(json_str)
        rescue StandardError
          []
        end

        db = services.find { |s| s["name"] =~ /postgres|db|database/i || s.dig("source", "image") =~ /postgres/i }
        db&.dig("name")
      rescue StandardError
        nil
      end

      def ensure_service_port!(environment, service, port:)
        runner.capture(
          "railway", "variable", "set", "PORT=#{port}",
          "--environment", environment.to_s,
          "--service", service.to_s
        )
      rescue StandardError
        nil
      end

      def cancel_duplicate_deployment!(environment, service)
        stdout, status = runner.capture("railway", "deployment", "list", "--service", service.to_s, "--environment", environment.to_s, "--json")
        return unless status&.success?

        json_str = stdout[/\[.*\]/m]
        return unless json_str

        deployments = begin
          JSON.parse(json_str)
        rescue StandardError
          []
        end

        in_flight = deployments.find { |d| %w[BUILDING INITIALIZING QUEUED].include?(d["status"]) }
        if in_flight && in_flight["id"]
          runner.capture("railway", "api", "mutation($id: String!) { deploymentCancel(id: $id) }", "--var", "id=#{in_flight['id']}")
        end
      rescue StandardError
        nil
      end

      def find_app_service(target_repo = nil, environment: nil, base_environment: nil)
        service = query_service(target_repo, environment: environment) if environment
        service ||= query_service(target_repo, environment: base_environment) if base_environment
        service ||= query_service(target_repo, environment: nil)
        service
      end

      def query_service(target_repo = nil, environment: nil)
        args = ["railway", "service", "list"]
        args += ["--environment", environment.to_s] if environment
        args << "--json"

        stdout, status = runner.capture(*args)
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

      def list_environments
        stdout, status = runner.capture("railway", "environment", "list", "--json")
        return [] unless status&.success?

        json_str = stdout[/\[.*\]/m]
        return [] unless json_str

        parsed = begin
          JSON.parse(json_str)
        rescue StandardError
          []
        end
        parsed.map { |e| e["name"] }
      rescue StandardError
        []
      end
    end
  end
end
