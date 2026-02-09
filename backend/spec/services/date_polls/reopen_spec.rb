# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::Reopen do
  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(user: owner)
    TestFactories.date_poll(event: event, closed_at: Time.now)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: other_user[:id],
      deadline: (Time.now + 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
  end

  it "returns failure when poll is not resolved" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      deadline: (Time.now + 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not resolved")
  end

  it "returns failure when deadline is missing" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event, closed_at: Time.now)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      deadline: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Deadline is required")
  end

  it "reopens the poll with a new deadline" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)
    DB[:date_polls].where(id: date_poll[:id]).update(selected_date_range_id: date_range[:id])
    new_deadline = (Time.now + 86_400).iso8601

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      deadline: new_deadline
    )

    expect(result.success?).to be true
    poll = result.value![:objects].find { |o| o[:objectType] == "datePoll" }
    expect(poll[:status]).to eq("open")
    expect(poll[:selectedDateRangeId]).to be_nil

    db_poll = DB[:date_polls].where(id: date_poll[:id]).first
    expect(db_poll[:closed_at]).to be_nil
    expect(db_poll[:selected_date_range_id]).to be_nil
  end
end
