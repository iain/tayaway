# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::Close do
  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: other_user[:id],
      selected_date_range_id: date_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
  end

  it "returns failure when poll is already resolved" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      selected_date_range_id: date_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is already resolved")
  end

  it "returns failure when selected_date_range_id is missing" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      selected_date_range_id: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("selected_date_range_id is required")
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
      selected_date_range_id: other_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range does not belong to this poll")
  end

  it "closes the poll and sets the winner" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      selected_date_range_id: date_range[:id]
    )

    expect(result.success?).to be true
    poll = result.value![:objects].find { |o| o[:objectType] == "datePoll" }
    expect(poll[:status]).to eq("resolved")
    expect(poll[:selectedDateRangeId]).to eq(date_range[:id])

    db_poll = DB[:date_polls].where(id: date_poll[:id]).first
    expect(db_poll[:closed_at]).not_to be_nil
    expect(db_poll[:selected_date_range_id]).to eq(date_range[:id])
  end
end
