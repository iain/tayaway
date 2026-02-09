# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::AddDateRange do
  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(user: owner)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: other_user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
  end

  it "returns failure when poll is not open" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event, closed_at: Time.now)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not open for changes")
  end

  it "returns failure when dates are invalid" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-10",
      end_date: "2024-06-01"
    )

    expect(result.failure?).to be true
  end

  it "adds a date range to the poll" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(result.success?).to be true
    date_range = result.value![:objects].find { |o| o[:objectType] == "dateRange" }
    expect(date_range).not_to be_nil
    expect(date_range[:datePollId]).to eq(date_poll[:id])
    expect(DB[:date_ranges].where(date_poll_id: date_poll[:id]).count).to eq(1)
  end
end
