# frozen_string_literal: true

require "spec_helper"

RSpec.describe VoteSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    it "returns an empty array for an empty input" do
      expect(described_class.serialize_batch([], pool: nil)).to eq([])
    end

    it "serializes vote fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      range = TestFactories.date_range(date_poll: poll)
      vote_row = TestFactories.vote(date_range: range, user: user, response: "yes", comment: "sure")
      vote = Vote.find(vote_row[:id])

      result = described_class.serialize_batch([vote], pool: nil).first

      expect(result[:id]).to eq(vote.id.to_s)
      expect(result[:objectType]).to eq("vote")
      expect(result[:dateRangeId]).to eq(range[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:response]).to eq("yes")
      expect(result[:comment]).to eq("sure")
      expect(result[:createdAt]).to match(/\.\d{3}/)
      expect(result[:updatedAt]).to match(/\.\d{3}/)
    end
  end

  describe ".policy_context_batch" do
    it "returns an empty hash for votes" do
      expect(described_class.policy_context_batch([])).to eq({})
    end
  end
end
