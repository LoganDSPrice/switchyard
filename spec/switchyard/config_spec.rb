# frozen_string_literal: true

require "spec_helper"
require "switchyard/config"
require "tmpdir"

RSpec.describe Switchyard::Config do
  subject(:config) { described_class.new(root_dir: dir) }

  let(:dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(dir) if File.exist?(dir)
  end

  context "when .switchyard.yml does not exist" do
    it "returns default configuration" do
      expect(config.adapter).to eq("railway")
      expect(config.pr_database_strategy).to eq("copy")
      expect(config.pr_default_db_source).to eq("auto")
      expect(config.app_service).to be_nil
    end
  end

  context "when .switchyard.yml exists with custom settings" do
    before do
      File.write(File.join(dir, ".switchyard.yml"), <<~YAML)
        adapter: railway
        service: web-app
        pr:
          database_strategy: seed
          default_db_source: production
      YAML
    end

    it "reads custom values from the configuration file" do
      expect(config.app_service).to eq("web-app")
      expect(config.pr_database_strategy).to eq("seed")
      expect(config.pr_default_db_source).to eq("production")
    end
  end
end
