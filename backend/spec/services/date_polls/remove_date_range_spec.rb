# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::RemoveDateRange do
  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: other_user[:id],
      date_range_id: date_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
  end

  it "returns failure when poll is not open" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      date_range_id: date_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not open for changes")
  end

  it "returns failure when date range does not belong to poll" do
    user = TestFactories.user
    event1 = TestFactories.event(user: user)
    event2 = TestFactories.event(user: user)
    TestFactories.date_poll(event: event1)
    other_poll = TestFactories.date_poll(event: event2)
    other_range = TestFactories.date_range(date_poll: other_poll)

    result = described_class.call(
      event_id: event1[:id],
      current_user_id: user[:id],
      date_range_id: other_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range does not belong to this poll")
  end

  it "removes a date range from the poll" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    dr_id = date_range[:id]

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      date_range_id: dr_id
    )

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "dateRange", id: dr_id }])
    expect(DB[:date_ranges].where(id: dr_id).count).to eq(0)
  end
end
