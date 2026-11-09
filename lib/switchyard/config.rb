# frozen_string_literal: true

require "yaml"

module Switchyard
  class Config
    CONFIG_FILENAME = ".switchyard.yml"

    DEFAULT_CONFIG = {
      "adapter" => "railway",
      "pr" => {
        "database_strategy" => "copy",
        "default_db_source" => "auto"
      }
    }.freeze

    def initialize(root_dir: Dir.pwd)
      @root_dir = root_dir
      @data = load_config
    end

    def adapter
      @data["adapter"] || "railway"
    end

    def pr_database_strategy
      @data.dig("pr", "database_strategy") || "copy"
    end

    def pr_default_db_source
      @data.dig("pr", "default_db_source") || "auto"
    end

    def app_service
      @data["app_service"] || @data["service"]
    end

    def port
      @data["port"] || @data.dig("pr", "port") || 80
    end

    def raw_data
      @data
    end

    private

    attr_reader :root_dir

    def load_config
      config_path = File.join(root_dir, CONFIG_FILENAME)
      return DEFAULT_CONFIG.dup unless File.exist?(config_path)

      loaded = YAML.safe_load(File.read(config_path), permitted_classes: [Symbol]) || {}
      deep_merge(DEFAULT_CONFIG, loaded)
    rescue StandardError
      DEFAULT_CONFIG.dup
    end

    def deep_merge(hash1, hash2)
      hash1.merge(hash2) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end
