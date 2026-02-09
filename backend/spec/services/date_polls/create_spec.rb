# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::Create do
  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(user: owner)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: other_user[:id],
      deadline: (Time.now + 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
  end

  it "returns failure when a poll already exists" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      deadline: (Time.now + 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("A date poll already exists for this event")
  end

  it "returns failure when deadline is missing" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      deadline: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Deadline is required")
  end

  it "returns failure when deadline is in the past" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      deadline: (Time.now - 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Deadline must be in the future")
  end

  it "creates a date poll and returns success" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    deadline = (Time.now + 86_400).iso8601

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      deadline: deadline
    )

    expect(result.success?).to be true
    poll = result.value![:objects].find { |o| o[:objectType] == "datePoll" }
    expect(poll).not_to be_nil
    expect(poll[:eventId]).to eq(event[:id])
    expect(poll[:status]).to eq("open")
    event_obj = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event_obj[:datePollId]).to eq(poll[:id])
  end
end
