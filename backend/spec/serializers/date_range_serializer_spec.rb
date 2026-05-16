# frozen_string_literal: true

require "spec_helper"

RSpec.describe DateRangeSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:event_row) { TestFactories.event(workspace: workspace, user: user) }
      let(:poll_row) { TestFactories.date_poll(event: event_row) }
      let(:range_row) { TestFactories.date_range(date_poll: poll_row) }
      let(:pool_object) { described_class.serialize_batch([DateRange.find(range_row[:id])], pool: nil).first }

      it_behaves_like "a pool object", "dateRange"
    end

    it "serializes date range fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      range_row = TestFactories.date_range(
        date_poll: poll, start_date: Date.today, end_date: Date.today + 3
      )
      range = DateRange.find(range_row[:id])

      result = described_class.serialize_batch([range], pool: nil).first

      expect(result[:id]).to eq(range.id.to_s)
      expect(result[:objectType]).to eq("dateRange")
      expect(result[:datePollId]).to eq(poll[:id].to_s)
      expect(result[:startDate]).to eq(Date.today.iso8601)
      expect(result[:endDate]).to eq((Date.today + 3).iso8601)
      expect(result[:updatedAt]).to match(/\.\d{3}/)
    end
  end

  describe ".policy_context_batch" do
    it "returns the event for each range" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      poll_row = TestFactories.date_poll(event: event_row)
      range_row = TestFactories.date_range(date_poll: poll_row)
      range = DateRange.find(range_row[:id])

      context = described_class.policy_context_batch([range])

      expect(context[range.id.to_s][:event]).to be_a(Event)
      expect(context[range.id.to_s][:event].id.to_s).to eq(event_row[:id].to_s)
    end

    it "batches date poll and event lookups across many ranges" do
      event1_row = TestFactories.event(workspace: workspace, user: user)
      event2_row = TestFactories.event(workspace: workspace, user: user)
      poll1_row = TestFactories.date_poll(event: event1_row)
      poll2_row = TestFactories.date_poll(event: event2_row)
      range1 = DateRange.find(TestFactories.date_range(date_poll: poll1_row)[:id])
      range2 = DateRange.find(TestFactories.date_range(date_poll: poll2_row)[:id])

      context = described_class.policy_context_batch([range1, range2])

      expect(context[range1.id.to_s][:event].id.to_s).to eq(event1_row[:id].to_s)
      expect(context[range2.id.to_s][:event].id.to_s).to eq(event2_row[:id].to_s)
    end
  end

  describe "policy context threading" do
    it "feeds DateRangePolicy the event kwarg it reads, avoiding the DatePoll.find + Event.find fallback" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      poll_row = TestFactories.date_poll(event: event_row)
      range_row = TestFactories.date_range(date_poll: poll_row)
      range = DateRange.find(range_row[:id])
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      membership = WorkspaceMembership.find(membership_row[:id])

      ctx = described_class.policy_context_batch([range])[range.id.to_s] || {}
      allow(DatePoll).to receive(:find).and_call_original
      allow(Event).to receive(:find).and_call_original

      expect(DateRangePolicy.new(range, membership: membership, **ctx).delete).to be_success
      expect(DatePoll).not_to have_received(:find)
      expect(Event).not_to have_received(:find)
    end
  end
end
