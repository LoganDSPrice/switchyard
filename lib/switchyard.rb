# frozen_string_literal: true

module Switchyard
  class Error < StandardError; end
end

require_relative "switchyard/version"
require_relative "switchyard/process_runner"
require_relative "switchyard/database_config"
require_relative "switchyard/adapters/base"
require_relative "switchyard/adapters/railway"
