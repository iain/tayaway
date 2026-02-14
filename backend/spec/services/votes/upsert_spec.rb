# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Votes::Upsert do
  it "returns failure when date_range_id is missing" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id], user_id: user[:id], date_range_id: nil, vote_response: "yes", comment: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("date_range_id is required")
  end

  it "returns failure when response is invalid" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id], user_id: user[:id], date_range_id: date_range[:id], vote_response: "invalid", comment: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid response value")
  end

  it "returns failure when date range not found" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id], user_id: user[:id], date_range_id: "00000000-0000-0000-0000-000000000000", vote_response: "yes", comment: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range not found")
  end

  it "returns failure when date range belongs to different event" do
    user = TestFactories.user
    event1 = TestFactories.event(user: user)
    event2 = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event2)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event1[:id], user_id: user[:id], date_range_id: date_range[:id], vote_response: "yes", comment: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range does not belong to this event")
  end

  it "returns failure when poll is not open" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id], user_id: user[:id], date_range_id: date_range[:id], vote_response: "yes", comment: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not open for voting")
  end

  it "creates new vote and returns created: true" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      user_id: user[:id],
      date_range_id: date_range[:id],
      vote_response: "yes",
      comment: "Looks good!"
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:vote_id]).to be_a(String)
    vote = DB[:votes].where(id: result.value![:vote_id]).first
    expect(vote[:response]).to eq("yes")
    expect(vote[:comment]).to eq("Looks good!")
  end

  it "updates existing vote and returns created: false" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    TestFactories.vote(user: user, date_range: date_range, response: "yes")

    result = described_class.call(
      event_id: event[:id],
      user_id: user[:id],
      date_range_id: date_range[:id],
      vote_response: "no",
      comment: "Changed my mind"
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be false
    vote = DB[:votes].where(id: result.value![:vote_id]).first
    expect(vote[:response]).to eq("no")
    expect(DB[:votes].count).to eq(1)
  end

  it "returns existing vote on idempotent replay with same vote_id" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    client_id = SecureRandom.uuid

    result1 = described_class.call(
      event_id: event[:id],
      user_id: user[:id],
      date_range_id: date_range[:id],
      vote_response: "yes",
      comment: nil,
      vote_id: client_id
    )
    result2 = described_class.call(
      event_id: event[:id],
      user_id: user[:id],
      date_range_id: date_range[:id],
      vote_response: "yes",
      comment: nil,
      vote_id: client_id
    )

    expect(result1.success?).to be true
    expect(result1.value![:created]).to be true
    expect(result2.success?).to be true
    expect(result2.value![:created]).to be false
    expect(DB[:votes].where(id: client_id).count).to eq(1)
  end
end
