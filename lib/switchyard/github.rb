# frozen_string_literal: true

require "json"
require_relative "process_runner"

module Switchyard
  class GitHub
    def initialize(runner: ProcessRunner.new)
      @runner = runner
    end

    def pr_info(identifier = nil)
      gh_info = fetch_from_gh(identifier)
      return gh_info if gh_info

      fallback_to_git(identifier)
    end

    def list_prs
      stdout, status = runner.capture("gh", "pr", "list", "--json", "number,title,headRefName")
      return [] unless status&.success?

      json_match = stdout[/\[.*\]/m]
      return [] unless json_match

      data = JSON.parse(json_match)
      data.map do |pr|
        {
          number: pr["number"],
          title: pr["title"],
          branch: pr["headRefName"]
        }
      end
    rescue StandardError
      []
    end

    def current_branch
      stdout, status = runner.capture("git", "branch", "--show-current")
      status&.success? ? stdout.strip : nil
    end

    def select_pr(shell = nil)
      prs = list_prs
      raise Error, "No open pull requests found." if prs.empty?

      active_branch = current_branch
      default_idx = prs.find_index { |pr| pr[:branch] == active_branch } || 0

      if shell
        shell.say "\nOpen Pull Requests:"
        prs.each_with_index do |pr, idx|
          is_default = (idx == default_idx)
          indicator = is_default ? "  👉" : "    "
          branch_info = "branch: #{pr[:branch]}"
          current_marker = is_default && pr[:branch] == active_branch ? " [Current Branch]" : ""
          shell.say "#{indicator} [#{idx + 1}] ##{pr[:number]} - #{pr[:title]} (#{branch_info})#{current_marker}"
        end

        input = shell.ask("\nSelect a PR [#{default_idx + 1}]:")
        chosen_idx = input.to_s.strip.empty? ? default_idx : (input.to_i - 1)
        prs[chosen_idx] || prs[default_idx]
      else
        prs[default_idx]
      end
    end

    private

    attr_reader :runner

    def fetch_from_gh(identifier)
      args = ["gh", "pr", "view"]
      args << identifier.to_s if identifier && identifier.to_s != "deploy"
      args += ["--json", "number,headRefName,headRepository"]

      stdout, status = runner.capture(*args)
      return unless status&.success?

      json_match = stdout[/{.*}/m]
      return unless json_match

      data = JSON.parse(json_match)
      {
        number: data["number"],
        branch: data["headRefName"],
        repo: data.dig("headRepository", "nameWithOwner")
      }
    rescue StandardError
      nil
    end

    def fallback_to_git(identifier)
      stdout, status = runner.capture("git", "remote", "get-url", "origin")
      unless status&.success?
        raise Error, "Could not determine GitHub repository. Make sure git origin remote is set or gh CLI is installed."
      end

      match = stdout.strip.match(/(?:github\.com[:\/])(?<owner>[\w\-]+)\/(?<repo>[\w\-\.]+?)(?:\.git)?\z/)
      unless match
        raise Error, "Could not determine GitHub repository from git remote. Make sure origin points to GitHub or gh CLI is installed."
      end

      repo = "#{match[:owner]}/#{match[:repo]}"

      branch_out, b_status = runner.capture("git", "branch", "--show-current")
      branch = b_status&.success? ? branch_out.strip : nil

      if branch.to_s.empty?
        raise Error, "Could not determine current branch. Please specify PR number explicitly or ensure branch is checked out."
      end

      number = identifier ? identifier.to_s.sub(/\Apr-?/i, "").to_i : nil

      {
        number: number,
        branch: branch,
        repo: repo
      }
    end
  end
end
