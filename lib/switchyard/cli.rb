# frozen_string_literal: true

require "thor"

module Switchyard
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    def initialize(args = [], local_options = {}, config = {})
      super
      @custom_config = config || {}
    end

    desc "console [ENV]", "Open a Rails console on the target environment (default: staging)"
    def console(environment = "staging", *args)
      adapter.console(environment, *args)
    end

    desc "logs [ENV]", "Stream real-time logs from the target environment (default: staging)"
    def logs(environment = "staging", *args)
      adapter.logs(environment, *args)
    end

    desc "migrate [ENV]", "Run database migrations on the target environment (default: staging)"
    def migrate(environment = "staging", *args)
      adapter.migrate(environment, *args)
    end

    desc "restore [FROM] [TO]", "Restore database from one environment into another (default TO: development)"
    method_option :force, type: :boolean, default: false, desc: "Bypass protected environment checks"
    def restore(from, to = "development")
      source_url = adapter.database_url(from)
      target_db = db_config.database_name(to)

      Database::Sync.new(
        source_url: source_url,
        target_db: target_db,
        target_env: to,
        force: options[:force]
      ).run!
    end

    desc "pr [NUMBER] [COMMAND]", "Execute a command against a PR preview environment"
    def pr(identifier, subcommand = "console", *args)
      env = adapter.resolve_pr_environment(identifier)

      case subcommand
      when "console"
        console(env, *args)
      when "logs"
        logs(env, *args)
      when "migrate"
        migrate(env, *args)
      when "restore"
        source_env = args.first || "staging"
        restore(source_env, env)
      else
        raise Error, "Unknown PR subcommand: #{subcommand}"
      end
    end

    private

    def adapter
      @custom_config[:adapter] || Adapters::Railway.new
    end

    def db_config
      @custom_config[:db_config] || DatabaseConfig.new
    end
  end
end
