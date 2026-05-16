# frozen_string_literal: true

require "spec_helper"

RSpec.describe VoteSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:event_row) { TestFactories.event(workspace: workspace, user: user) }
      let(:poll_row) { TestFactories.date_poll(event: event_row) }
      let(:range_row) { TestFactories.date_range(date_poll: poll_row) }
      let(:vote_row) { TestFactories.vote(date_range: range_row, user: user) }
      let(:pool_object) { described_class.serialize_batch([Vote.find(vote_row[:id])], pool: nil).first }

      it_behaves_like "a pool object with createdAt", "vote"
    end

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

  describe "policy context" do
    it "does not define a policy_context_batch — PoolSerializer falls back to {} via respond_to?" do
      expect(described_class).not_to respond_to(:policy_context_batch)
    end
  end
end
