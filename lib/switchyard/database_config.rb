# frozen_string_literal: true

require "erb"
require "yaml"

module Switchyard
  class DatabaseConfig
    class FileNotFoundError < Error; end
    class ConfigurationError < Error; end

    DEFAULT_PATH = "config/database.yml"
    PRIMARY_KEY = "primary"
    DATABASE_KEY = "database"

    def initialize(config_path: DEFAULT_PATH)
      @config_path = config_path
    end

    def database_name(environment, role: PRIMARY_KEY)
      ensure_file_exists!

      env_config = parsed_yaml.fetch(environment.to_s) do
        raise ConfigurationError, "Environment '#{environment}' not found in #{@config_path}"
      end

      if env_config.key?(DATABASE_KEY)
        env_config.fetch(DATABASE_KEY)
      elsif env_config.key?(role) && env_config[role].key?(DATABASE_KEY)
        env_config[role].fetch(DATABASE_KEY)
      else
        first_configured = env_config.values.find { |v| v.is_a?(Hash) && v.key?(DATABASE_KEY) }
        first_configured&.fetch(DATABASE_KEY) || raise(ConfigurationError, "Could not determine database name for '#{environment}'")
      end
    end

    private

    attr_reader :config_path

    def ensure_file_exists!
      return if File.exist?(config_path)

      raise FileNotFoundError, "Database configuration file #{config_path} not found"
    end

    def parsed_yaml
      raw = File.read(config_path)
      rendered = ERB.new(raw).result
      YAML.safe_load(rendered, aliases: true) || {}
    end
  end
end
