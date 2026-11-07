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
end
