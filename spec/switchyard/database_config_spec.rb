# frozen_string_literal: true

require "spec_helper"
require "switchyard/database_config"

RSpec.describe Switchyard::DatabaseConfig do
  subject(:db_config) { described_class.new(config_path: config_path) }

  let(:config_path) { "config/database.yml" }

  describe "#database_name" do
    context "with a standard Rails 2-tier database.yml" do
      let(:yaml_content) do
        <<~YAML
          default: &default
            adapter: postgresql
            encoding: unicode

          development:
            <<: *default
            database: myapp_development

          test:
            <<: *default
            database: myapp_test
        YAML
      end

      before do
        allow(File).to receive(:read).with(config_path).and_return(yaml_content)
        allow(File).to receive(:exist?).with(config_path).and_return(true)
      end

      it "extracts the database name for the requested environment" do
        expect(db_config.database_name("development")).to eq("myapp_development")
        expect(db_config.database_name("test")).to eq("myapp_test")
      end
    end

    context "with ERB tags in database.yml" do
      let(:yaml_content) do
        <<~YAML
          development:
            database: <%= "myapp" %>_<%= "dev" %>
        YAML
      end

      before do
        allow(File).to receive(:read).with(config_path).and_return(yaml_content)
        allow(File).to receive(:exist?).with(config_path).and_return(true)
      end

      it "evaluates ERB expressions correctly" do
        expect(db_config.database_name("development")).to eq("myapp_dev")
      end
    end

    context "with Rails 6+ 3-tier multi-database configuration" do
      let(:yaml_content) do
        <<~YAML
          development:
            primary:
              database: myapp_primary_dev
            animals:
              database: myapp_animals_dev
        YAML
      end

      before do
        allow(File).to receive(:read).with(config_path).and_return(yaml_content)
        allow(File).to receive(:exist?).with(config_path).and_return(true)
      end

      it "picks the primary database name by default" do
        expect(db_config.database_name("development")).to eq("myapp_primary_dev")
      end
    end

    context "when config file does not exist" do
      before do
        allow(File).to receive(:exist?).with(config_path).and_return(false)
      end

      it "raises a helpful error" do
        expect do
          db_config.database_name("development")
        end.to raise_error(Switchyard::DatabaseConfig::FileNotFoundError, %r{config/database.yml not found})
      end
    end
  end
end
