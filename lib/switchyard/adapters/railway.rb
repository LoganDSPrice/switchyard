# frozen_string_literal: true

require "json"
require_relative "base"

module Switchyard
  module Adapters
    class Railway < Base
      class CommandError < Error; end
      class VariableNotFoundError < Error; end

      DATABASE_KEYS = %w[DATABASE_PUBLIC_URL DATABASE_URL].freeze
      MAX_ENV_READY_ATTEMPTS = 5
      MAX_EDIT_ATTEMPTS = 3
      RETRY_DELAY_SECONDS = 2

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
        env_entries = fetch_environments
        environments = env_entries.map { |e| e["name"] }
        created = !environments.include?(environment.to_s)
        previous_env = created ? linked_environment_name(env_entries) : nil

        create_environment!(environment, duplicate_from: base_environment, existing_environments: environments) if created

        resolved_service = resolve_service_id(service || @service, repo: repo, environment: environment, base_environment: base_environment)
        raise CommandError, "Could not identify app service for deployment. Specify service via --service or config." unless resolved_service

        initial_config = created ? wait_for_environment_config(environment, resolved_service) : nil
        apply_and_verify_environment_edit!(environment, service_id: resolved_service, repo: repo, branch: branch, port: port, initial_config: initial_config)

        true
      ensure
        restore_linked_environment(previous_env) if created && previous_env && previous_env != environment.to_s
      end

      private

      def create_environment!(environment, duplicate_from:, existing_environments:)
        base = duplicate_from if existing_environments.include?(duplicate_from.to_s)
        base ||= "staging" if existing_environments.include?("staging")
        base ||= "production" if existing_environments.include?("production")
        base ||= existing_environments.first

        cmd = ["railway", "environment", "new", environment.to_s]
        cmd += ["--duplicate", base.to_s] if base
        cmd << "--json"

        stdout, status = runner.capture(*cmd)
        return if status&.success?

        raise CommandError, "Failed to create Railway environment '#{environment}'#{" duplicating '#{base}'" if base}: #{stdout&.strip}"
      end

      def wait_for_environment_config(environment, service_id)
        MAX_ENV_READY_ATTEMPTS.times do |attempt|
          config = fetch_environment_config(environment)
          return config if config&.dig("services", service_id.to_s)

          pause(RETRY_DELAY_SECONDS) if attempt < MAX_ENV_READY_ATTEMPTS - 1
        end
        nil
      end

      def apply_and_verify_environment_edit!(environment, service_id:, repo:, branch:, port:, initial_config: nil)
        pre_config = initial_config

        MAX_EDIT_ATTEMPTS.times do |attempt|
          cancel_duplicate_deployment!(environment, service_id)
          pre_config ||= fetch_environment_config(environment)
          cmd = build_environment_edit_command(
            environment,
            service_id: service_id,
            repo: repo,
            branch: branch,
            port: port,
            env_config: pre_config
          )

          stdout, status = runner.capture(*cmd)
          raise CommandError, "Failed to update environment '#{environment}' on Railway: #{stdout&.strip}" unless status&.success?

          post_config = fetch_environment_config(environment)
          return true if environment_config_matches?(post_config, service_id, branch: branch, port: port)

          pre_config = post_config
          pause(RETRY_DELAY_SECONDS) if attempt < MAX_EDIT_ATTEMPTS - 1
        end

        raise CommandError,
              "Failed to verify environment '#{environment}' configuration on Railway (expected branch '#{branch}'#{", PORT=#{port}" if port})."
      end

      def environment_config_matches?(config, service_id, branch:, port:)
        svc_cfg = config&.dig("services", service_id.to_s)
        return false unless svc_cfg
        return false unless svc_cfg.dig("source", "branch") == branch.to_s
        return true unless port

        current_port = svc_cfg.dig("variables", "PORT", "value") || svc_cfg.dig("variables", "PORT")
        current_port.to_s == port.to_s
      end

      def linked_environment_name(env_entries)
        linked = env_entries.find { |e| e["isLinked"] == true }
        linked&.dig("name") || linked&.dig("id")
      end

      def restore_linked_environment(environment)
        return unless environment

        runner.capture("railway", "environment", "link", environment.to_s, "--json")
      rescue StandardError
        nil
      end

      def pause(seconds)
        sleep(seconds)
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

      def build_environment_edit_command(environment, service_id:, repo:, branch:, port:, env_config: nil)
        cmd = ["railway", "environment", "edit", "--environment", environment.to_s]
        repo_connected = env_config&.dig("services", service_id.to_s, "source", "repo") == repo.to_s
        cmd += ["--service-config", service_id.to_s, "source.repo", repo.to_s] unless repo_connected
        cmd += ["--service-config", service_id.to_s, "source.branch", branch.to_s]
        cmd += ["--service-config", service_id.to_s, "variables.PORT.value", port.to_s] if port
        cmd += ["-m", deploy_commit_message(environment, branch), "--json"]
        cmd
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

      def fetch_environments
        stdout, status = runner.capture("railway", "environment", "list", "--json")
        return [] unless status&.success?

        parse_json_array(stdout)
      rescue StandardError
        []
      end

      def list_environments
        fetch_environments.map { |e| e["name"] }
      end

      def parse_json_array(stdout)
        parse_json_matching(stdout, /\[.*\]/m, Array) || []
      end

      def parse_json_object(stdout)
        parse_json_matching(stdout, /\{.*\}/m, Hash)
      end

      def parse_json_matching(stdout, pattern, expected_class)
        json_str = stdout.to_s[pattern]
        return nil unless json_str

        parsed = JSON.parse(json_str)
        parsed.is_a?(expected_class) ? parsed : nil
      rescue StandardError
        nil
      end
    end
  end
end
