# frozen_string_literal: true

require "thor"

module Switchyard
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    def self.help(shell, subcommand = false)
      list = printable_commands(true, subcommand)
      Thor::Util.thor_classes_in(self).each do |klass|
        list += klass.printable_commands(false)
      end
      list.sort! { |a, b| a[0] <=> b[0] }

      shell.say "Switchyard — Environment & Database Parity for Rails on Railway"
      shell.say
      shell.say "USAGE:"
      shell.say "  switchyard [COMMAND] [ARGS]"
      shell.say "  # Or run the generated environment binstubs:"
      shell.say "  [dev|staging|production|pr] [COMMAND] [ARGS]"
      shell.say
      shell.say "CORE COMMANDS:"
      shell.print_table(list, indent: 2, truncate: true)
      shell.say
      shell.say "BINSTUB SHORTCUTS (Recommended):"
      shell.say "  dev restore <from>                # e.g. `dev restore staging` (pulls remote DB into local dev)"
      shell.say "  staging console                   # Opens remote Rails console on staging via SSH"
      shell.say "  production console                # Opens remote Rails console on production via SSH"
      shell.say "  staging logs                      # Streams real-time logs"
      shell.say "  staging migrate                   # Runs remote database migrations via SSH"
      shell.say "  pr <number> console               # e.g. `pr 142 console` (console in PR preview app)"
      shell.say "  pr <number> restore <from>        # e.g. `pr 142 restore staging` (seeds PR database from staging)"
      shell.say
      shell.say "Run `switchyard help [COMMAND]` for detailed flags on any command."
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

    desc "install", "Generate binstubs and default configuration in a Rails project"
    method_option :git_safe, type: :boolean, default: false, desc: "Create .git/safe to allow running binstubs without 'bin/' prefix"
    method_option :github_action, type: :boolean, default: false, desc: "Generate GitHub Action workflow to auto-decommission PR review apps when closed"
    def install
      installer = Installer.new(
        destination: Dir.pwd,
        git_safe: options[:git_safe],
        github_action: options[:github_action]
      )
      installer.install!
      puts "✨ Switchyard installed successfully!"
      puts "Generated binstubs in bin/: switchyard, dev, staging, production, pr"
      puts "Generated configuration: .switchyard.yml"

      if installer.github_action_generated?
        puts "🤖 Generated .github/workflows/switchyard-cleanup-pr.yml!"
        puts "   To enable automated cleanup:"
        puts "   1. On Railway: Project Settings → Tokens → New Token"
        puts "      • Name suggestion: 'GitHub Actions - PR Cleanup' (Project Token)"
        if (secrets_url = installer.github_secrets_url)
          puts "   2. On GitHub: Add the secret directly at:"
          puts "      👉 #{secrets_url}"
        else
          puts "   2. On GitHub: Settings → Secrets and variables → Actions → New repository secret"
        end
        puts "      • Name:   RAILWAY_TOKEN"
        puts "      • Secret: [Paste the copied Railway token]"
      end

      if installer.git_safe_enabled?
        puts "🔒 Enabled .git/safe! Local binstubs will supersede any global asdf shims if .git/safe/../../bin is in your PATH."
      else
        puts "\n💡 Quick Tip:"
        puts "  Run commands via their project binstub (e.g. `bin/staging console`)."
        puts "  To omit `bin/`, run `switchyard install --git-safe` or create `.git/safe` manually."
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
