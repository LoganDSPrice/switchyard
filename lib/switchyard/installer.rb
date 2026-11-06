# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Switchyard
  class Installer
    class NotInRailsProjectError < Error; end

    BINSTUBS = {
      "dev" => <<~RUBY,
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        require "bundler/setup"
        require "switchyard"

        subcommand = ARGV.first
        args = ARGV.drop(1)

        case subcommand
        when "restore", "restore-from"
          from = args.first || "staging"
          Switchyard::CLI.start(["restore", from, "development"] + args.drop(1))
        when "console"
          Kernel.system("bin/rails", "console", *args)
        when "migrate"
          Kernel.system("bin/rails", "db:migrate", *args)
        when nil, "help", "--help", "-h"
          puts "Usage: dev [console|migrate|restore <env>]"
        else
          Kernel.system(subcommand, *args)
        end
      RUBY

      "staging" => <<~RUBY,
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        require "bundler/setup"
        require "switchyard"

        subcommand = ARGV.first || "console"
        args = ARGV.drop(1)

        case subcommand
        when "console"
          Switchyard::CLI.start(["console", "staging"] + args)
        when "logs", "tail"
          Switchyard::CLI.start(["logs", "staging"] + args)
        when "migrate"
          Switchyard::CLI.start(["migrate", "staging"] + args)
        when "restore", "restore-from"
          from = args.first || "production"
          Switchyard::CLI.start(["restore", from, "staging"] + args.drop(1))
        when "help", "--help", "-h"
          puts "Usage: staging [console|logs|migrate|restore <from>]"
        else
          Switchyard::CLI.start([subcommand, "staging"] + args)
        end
      RUBY

      "production" => <<~RUBY,
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        require "bundler/setup"
        require "switchyard"

        subcommand = ARGV.first || "console"
        args = ARGV.drop(1)

        case subcommand
        when "console"
          Switchyard::CLI.start(["console", "production"] + args)
        when "logs", "tail"
          Switchyard::CLI.start(["logs", "production"] + args)
        when "migrate"
          Switchyard::CLI.start(["migrate", "production"] + args)
        when "restore", "restore-from"
          from = args.first || "staging"
          Switchyard::CLI.start(["restore", from, "production"] + args.drop(1))
        when "help", "--help", "-h"
          puts "Usage: production [console|logs|migrate|restore <from>]"
        else
          Switchyard::CLI.start([subcommand, "production"] + args)
        end
      RUBY

      "pr" => <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        require "bundler/setup"
        require "switchyard"

        if ARGV.empty? || ARGV.first =~ /\\A(-h|--help|help)\\z/
          puts "Usage: pr <number> [console|logs|migrate|restore <from>]"
          exit 0
        end

        identifier = ARGV.first
        subcommand = ARGV[1] || "console"
        args = ARGV.drop(2)

        Switchyard::CLI.start(["pr", identifier, subcommand] + args)
      RUBY
    }.freeze

    DEFAULT_CONFIG = <<~YAML
      # Switchyard Configuration
      adapter: railway
      environments:
        development:
          database_role: primary
        staging:
          name: staging
        production:
          name: production
    YAML

    def initialize(destination: Dir.pwd, runner: ProcessRunner.new, git_safe: false)
      @destination = destination
      @runner = runner
      @git_safe = git_safe
      @git_safe_enabled = false
    end

    def install!
      validate_rails_directory!

      generate_binstubs!
      generate_config!
      enable_git_safe! if git_safe

      true
    end

    def git_safe_enabled?
      @git_safe_enabled
    end

    private

    attr_reader :destination, :runner, :git_safe

    def validate_rails_directory!
      has_db_config = File.exist?(File.join(destination, "config", "database.yml"))
      has_app_config = File.exist?(File.join(destination, "config", "application.rb"))

      return if has_db_config || has_app_config

      raise NotInRailsProjectError,
            "Could not find config/database.yml or config/application.rb in #{destination}. Make sure you are in a Rails project root."
    end

    def generate_binstubs!
      bin_dir = File.join(destination, "bin")
      FileUtils.mkdir_p(bin_dir)

      BINSTUBS.each do |name, content|
        binstub_path = File.join(bin_dir, name)
        File.write(binstub_path, content)
        FileUtils.chmod(0o755, binstub_path)
      end
    end

    def generate_config!
      config_path = File.join(destination, ".switchyard.yml")
      return if File.exist?(config_path)

      File.write(config_path, DEFAULT_CONFIG)
    end

    def enable_git_safe!
      git_dir = File.join(destination, ".git")
      return unless Dir.exist?(git_dir)

      FileUtils.mkdir_p(File.join(git_dir, "safe"))
      @git_safe_enabled = true
    end
  end
end
