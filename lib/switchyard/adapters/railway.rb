# frozen_string_literal: true

require "json"
require_relative "base"

module Switchyard
  module Adapters
    class Railway < Base
      class CommandError < Error; end
      class VariableNotFoundError < Error; end

      DATABASE_KEYS = %w[DATABASE_PUBLIC_URL DATABASE_URL].freeze

      attr_reader :service

      def initialize(runner: ProcessRunner.new, service: nil)
        super(runner: runner)
        @service = service
      end

      def console(environment, *args, service: nil)
        svc = service || @service
        cmd = ["railway", "ssh", "--environment", environment.to_s]
        cmd += ["--service", svc.to_s] if svc
        cmd += ["--", "bin/rails", "console", *args]
        runner.exec(*cmd)
      end

      def logs(environment, *args, service: nil)
        svc = service || @service
        cmd = ["railway", "logs", "--environment", environment.to_s]
        cmd += ["--service", svc.to_s] if svc
        cmd += args
        runner.exec(*cmd)
      end

      def migrate(environment, *args, service: nil)
        svc = service || @service
        cmd = ["railway", "ssh", "--environment", environment.to_s]
        cmd += ["--service", svc.to_s] if svc
        cmd += ["--", "bin/rails", "db:migrate", *args]
        runner.system(*cmd)
      end

      def seed(environment, *args, service: nil)
        svc = service || @service
        cmd = ["railway", "ssh", "--environment", environment.to_s]
        cmd += ["--service", svc.to_s] if svc
        cmd += ["--", "bin/rails", "db:seed", *args]
        runner.system(*cmd)
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

        raise CommandError, "Failed to fetch variables for environment '#{environment}': #{stdout&.strip}" unless status&.success?

        parsed = parse_json_object(stdout)
        raise CommandError, "Failed to parse variables for environment '#{environment}': #{stdout&.strip}" unless parsed

        url_key = DATABASE_KEYS.find { |key| parsed.key?(key) && !parsed[key].to_s.empty? }

        url_key ? parsed[url_key] : raise(VariableNotFoundError, "Neither DATABASE_PUBLIC_URL nor DATABASE_URL found in environment '#{environment}'")
      end

      def resolve_pr_environment(identifier)
        clean = identifier.to_s.sub(/\Apr-?/i, "")
        "pr-#{clean}"
      end

      def deploy_pr(environment, repo:, branch:, service: nil, base_environment: "staging", port: nil)
        ensure_environment_exists!(environment, duplicate_from: base_environment)
        resolved_service = resolve_service_id(
          service || @service,
          repo: repo,
          environment: environment,
          base_environment: base_environment
        )

        raise CommandError, "Could not identify app service for deployment. Specify service via --service or config." unless resolved_service

        cancel_duplicate_deployment!(environment, resolved_service)

        cmd = build_environment_edit_command(
          environment,
          service_id: resolved_service,
          repo: repo,
          branch: branch,
          port: port
        )

        stdout, status = runner.capture(*cmd)
        raise CommandError, "Failed to update environment '#{environment}' on Railway: #{stdout&.strip}" unless status&.success?

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
        return if status&.success?

        raise CommandError, "Failed to create Railway environment '#{environment}'#{" duplicating '#{base}'" if base}: #{stdout&.strip}"
      end

      def resolve_service_id(target_service, repo:, environment:, base_environment:)
        if target_service
          matched = list_services(environment: environment).find do |s|
            s["id"] == target_service.to_s || s["name"] == target_service.to_s
          end
          return matched["id"] || matched["name"] if matched

          return target_service.to_s
        end

        matched = find_app_service(repo, environment: environment, base_environment: base_environment)
        matched&.dig("id") || matched&.dig("name")
      end

      def build_environment_edit_command(environment, service_id:, repo:, branch:, port:)
        cmd = ["railway", "environment", "edit", "--environment", environment.to_s]
        cmd += ["--service-config", service_id.to_s, "source.repo", repo.to_s] unless service_repo_connected?(environment, service_id, repo)
        cmd += ["--service-config", service_id.to_s, "source.branch", branch.to_s]
        cmd += ["--service-config", service_id.to_s, "variables.PORT.value", port.to_s] if port
        cmd += ["-m", deploy_commit_message(environment, branch), "--json"]
        cmd
      end

      def service_repo_connected?(environment, service_id, repo)
        config = fetch_environment_config(environment)
        config&.dig("services", service_id.to_s, "source", "repo") == repo.to_s
      end

      def fetch_environment_config(environment)
        stdout, status = runner.capture("railway", "environment", "config", "--environment", environment.to_s, "--json")
        return nil unless status&.success?

        parse_json_object(stdout)
      rescue StandardError
        nil
      end

      def deploy_commit_message(environment, branch)
        label = if environment.to_s =~ /\Apr-(\d+)\z/i
                  "PR ##{Regexp.last_match(1)}"
                else
                  environment.to_s
                end
        "Deploy #{label} (#{branch})"
      end

      def find_db_service(environment: nil)
        services = list_services(environment: environment)
        db = services.find { |s| s["name"] =~ /postgres|db|database/i || s.dig("source", "image") =~ /postgres/i }
        db&.dig("name")
      rescue StandardError
        nil
      end

      def cancel_duplicate_deployment!(environment, service)
        stdout, status = runner.capture("railway", "deployment", "list", "--service", service.to_s, "--environment", environment.to_s, "--json")
        return unless status&.success?

        deployments = parse_json_array(stdout)
        in_flight = deployments.select { |d| %w[BUILDING INITIALIZING QUEUED].include?(d["status"]) && d["id"] }
        in_flight.each do |deployment|
          runner.capture("railway", "api", "mutation($id: String!) { deploymentCancel(id: $id) }", "--var", "id=#{deployment['id']}")
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
        services = list_services(environment: environment)
        return nil if services.empty?

        matching = services.find { |s| s.dig("source", "repo") == target_repo } if target_repo
        matching ||= services.find { |s| s.dig("source", "repo") }
        matching ||= services.find { |s| s["name"] !~ /postgres|redis|mysql|db/i }
        matching || services.first
      rescue StandardError
        nil
      end

      def list_services(environment: nil)
        args = %w[railway service list]
        args += ["--environment", environment.to_s] if environment
        args << "--json"

        stdout, status = runner.capture(*args)
        return [] unless status&.success?

        parse_json_array(stdout)
      rescue StandardError
        []
      end

      def list_environments
        stdout, status = runner.capture("railway", "environment", "list", "--json")
        return [] unless status&.success?

        parse_json_array(stdout).map { |e| e["name"] }
      rescue StandardError
        []
      end

      def parse_json_array(stdout)
        json_str = stdout.to_s[/\[.*\]/m]
        return [] unless json_str

        parsed = JSON.parse(json_str)
        parsed.is_a?(Array) ? parsed : []
      rescue StandardError
        []
      end

      def parse_json_object(stdout)
        json_str = stdout.to_s[/\{.*\}/m]
        return nil unless json_str

        parsed = JSON.parse(json_str)
        parsed.is_a?(Hash) ? parsed : nil
      rescue StandardError
        nil
      end
    end
  end
end
