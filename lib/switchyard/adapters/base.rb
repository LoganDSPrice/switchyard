# frozen_string_literal: true

require_relative "../process_runner"

module Switchyard
  module Adapters
    class Base
      def initialize(runner: ProcessRunner.new)
        @runner = runner
      end

      def console(environment, *args)
        raise NotImplementedError
      end

      def logs(environment, *args)
        raise NotImplementedError
      end

      def migrate(environment, *args)
        raise NotImplementedError
      end

      def seed(environment, *args)
        raise NotImplementedError
      end

      def resolve_base_environment
        raise NotImplementedError
      end

      def database_url(environment)
        raise NotImplementedError
      end

      def resolve_pr_environment(identifier)
        raise NotImplementedError
      end

      def deploy_pr(environment, repo:, branch:, **options)
        raise NotImplementedError
      end

      private

      attr_reader :runner
    end
  end
end
