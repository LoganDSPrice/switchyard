# frozen_string_literal: true

require "spec_helper"
require "switchyard/github"

RSpec.describe Switchyard::GitHub do
  subject(:github) { described_class.new(runner: runner) }

  let(:runner) { instance_double("Switchyard::ProcessRunner") }

  describe "#pr_info" do
    context "when gh CLI returns PR details" do
      let(:gh_output) do
        <<~JSON
          {
            "number": 157,
            "headRefName": "test/preview-app-banner",
            "headRepository": {
              "nameWithOwner": "LoganDSPrice/NBA-Over-Under-Redux"
            }
          }
        JSON
      end

      it "parses and returns number, branch, and repo from gh with explicit identifier" do
        expect(runner).to receive(:capture).with(
          "gh", "pr", "view", "157", "--json", "number,headRefName,headRepository"
        ).and_return([gh_output, double(success?: true)])

        info = github.pr_info("157")
        expect(info[:number]).to eq(157)
        expect(info[:branch]).to eq("test/preview-app-banner")
        expect(info[:repo]).to eq("LoganDSPrice/NBA-Over-Under-Redux")
      end

      it "parses and returns number, branch, and repo without identifier (auto-detecting current branch PR)" do
        expect(runner).to receive(:capture).with(
          "gh", "pr", "view", "--json", "number,headRefName,headRepository"
        ).and_return([gh_output, double(success?: true)])

        info = github.pr_info
        expect(info[:number]).to eq(157)
        expect(info[:branch]).to eq("test/preview-app-banner")
        expect(info[:repo]).to eq("LoganDSPrice/NBA-Over-Under-Redux")
      end
    end

    context "when gh CLI is not available or fails" do
      it "falls back to git origin remote and current branch" do
        expect(runner).to receive(:capture).with(
          "gh", "pr", "view", "157", "--json", "number,headRefName,headRepository"
        ).and_return(["command not found", double(success?: false)])

        expect(runner).to receive(:capture).with(
          "git", "remote", "get-url", "origin"
        ).and_return(["git@github.com:LoganDSPrice/NBA-Over-Under-Redux.git\n", double(success?: true)])

        expect(runner).to receive(:capture).with(
          "git", "branch", "--show-current"
        ).and_return(["test/preview-app-banner\n", double(success?: true)])

        info = github.pr_info("157")
        expect(info[:number]).to eq(157)
        expect(info[:branch]).to eq("test/preview-app-banner")
        expect(info[:repo]).to eq("LoganDSPrice/NBA-Over-Under-Redux")
      end

      it "raises an error if repo cannot be determined" do
        expect(runner).to receive(:capture).with(
          "gh", "pr", "view", "157", "--json", "number,headRefName,headRepository"
        ).and_return(["command not found", double(success?: false)])

        expect(runner).to receive(:capture).with(
          "git", "remote", "get-url", "origin"
        ).and_return(["fatal: not a git repo", double(success?: false)])

        expect {
          github.pr_info("157")
        }.to raise_error(Switchyard::Error, /Could not determine GitHub repository/)
      end
    end
  end

  describe "#list_prs" do
    let(:list_json) do
      <<~JSON
        [
          {
            "number": 157,
            "title": "test: Railway PR preview app verification",
            "headRefName": "test/preview-app-banner"
          },
          {
            "number": 155,
            "title": "chore(deps): bump dependencies",
            "headRefName": "dependabot/bundler"
          }
        ]
      JSON
    end

    it "queries gh pr list and returns structured PR list" do
      expect(runner).to receive(:capture).with(
        "gh", "pr", "list", "--json", "number,title,headRefName"
      ).and_return([list_json, double(success?: true)])

      prs = github.list_prs
      expect(prs.size).to eq(2)
      expect(prs.first[:number]).to eq(157)
      expect(prs.first[:title]).to eq("test: Railway PR preview app verification")
      expect(prs.first[:branch]).to eq("test/preview-app-banner")
    end

    it "returns empty array when gh command fails" do
      expect(runner).to receive(:capture).with(
        "gh", "pr", "list", "--json", "number,title,headRefName"
      ).and_return(["error", double(success?: false)])

      expect(github.list_prs).to eq([])
    end
  end

  describe "#select_pr" do
    let(:prs) do
      [
        { number: 157, title: "test: Railway PR preview app verification", branch: "test/preview-app-banner" },
        { number: 155, title: "chore(deps): bump dependencies", branch: "dependabot/bundler" }
      ]
    end

    let(:shell) { instance_double("Thor::Shell::Basic") }

    before do
      allow(github).to receive(:list_prs).and_return(prs)
      allow(github).to receive(:current_branch).and_return("test/preview-app-banner")
    end

    it "displays the list of open PRs marking the current branch as default and returns selected PR" do
      expect(shell).to receive(:say).with("\nOpen Pull Requests:")
      expect(shell).to receive(:say).with("  👉 [1] #157 - test: Railway PR preview app verification (branch: test/preview-app-banner) [Current Branch]")
      expect(shell).to receive(:say).with("     [2] #155 - chore(deps): bump dependencies (branch: dependabot/bundler)")
      expect(shell).to receive(:ask).with("\nSelect a PR [1]:").and_return("")

      selected = github.select_pr(shell)
      expect(selected[:number]).to eq(157)
    end

    it "allows selecting a different PR by number index" do
      allow(shell).to receive(:say)
      expect(shell).to receive(:ask).with("\nSelect a PR [1]:").and_return("2")

      selected = github.select_pr(shell)
      expect(selected[:number]).to eq(155)
    end

    it "raises an error if no open PRs exist" do
      allow(github).to receive(:list_prs).and_return([])
      expect {
        github.select_pr(shell)
      }.to raise_error(Switchyard::Error, /No open pull requests found/)
    end
  end
end
