# frozen_string_literal: true

require "spec_helper"

RSpec.describe DateRangeSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
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
end
