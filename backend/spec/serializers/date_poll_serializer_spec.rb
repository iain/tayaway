# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePollSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:event_row) { TestFactories.event(workspace: workspace, user: user) }
      let(:poll_row) { TestFactories.date_poll(event: event_row) }
      let(:pool_object) { described_class.serialize_batch([DatePoll.find(poll_row[:id])], pool: nil).first }

      it_behaves_like "a pool object with createdAt", "datePoll"
    end

    it "returns an empty array for empty input" do
      expect(described_class.serialize_batch([], pool: nil)).to eq([])
    end

    it "serializes poll fields with batched dateRangeIds" do
      event1 = TestFactories.event(workspace: workspace, user: user)
      event2 = TestFactories.event(workspace: workspace, user: user)
      poll1 = TestFactories.date_poll(event: event1)
      poll2 = TestFactories.date_poll(event: event2)
      range = TestFactories.date_range(date_poll: poll1)

      polls = [DatePoll.find(poll1[:id]), DatePoll.find(poll2[:id])]
      result = described_class.serialize_batch(polls, pool: nil)

      expect(result[0][:objectType]).to eq("datePoll")
      expect(result[0][:eventId]).to eq(event1[:id].to_s)
      expect(result[0][:dateRangeIds]).to include(range[:id].to_s)
      expect(result[1][:dateRangeIds]).to eq([])
    end
  end

  describe ".policy_context_batch" do
    it "returns the event and date-option count for each date poll" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      poll_row = TestFactories.date_poll(event: event_row)
      TestFactories.date_range(date_poll: poll_row)
      poll = DatePoll.find(poll_row[:id])

      context = described_class.policy_context_batch([poll])

      expect(context[poll.id.to_s][:event]).to be_a(Event)
      expect(context[poll.id.to_s][:event].id.to_s).to eq(event_row[:id].to_s)
      expect(context[poll.id.to_s][:date_range_count]).to eq(1)
    end
  end

  describe "policy context threading" do
    it "feeds DatePollPolicy the kwargs it reads, avoiding its per-poll fallback queries" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      poll_row = TestFactories.date_poll(event: event_row)
      TestFactories.date_range(date_poll: poll_row)
      poll = DatePoll.find(poll_row[:id])
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      membership = WorkspaceMembership.find(membership_row[:id])

      ctx = described_class.policy_context_batch([poll])[poll.id.to_s] || {}
      allow(Event).to receive(:find).and_call_original
      allow(DateRange).to receive(:count_for_date_poll).and_call_original

      expect(DatePollPolicy.new(poll, membership: membership, **ctx).close).to be_success
      expect(Event).not_to have_received(:find)
      expect(DateRange).not_to have_received(:count_for_date_poll)
    end
  end
end
