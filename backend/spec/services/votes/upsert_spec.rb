# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Votes::Upsert do
  it "returns failure when date_range_id is missing" do
    user = create(:user)
    event = create(:event, user: user)

    result = described_class.call(
      event: event, user_id: user.id, date_range_id: nil, vote_response: "yes", comment: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("date_range_id is required")
  end

  it "returns failure when response is invalid" do
    user = create(:user)
    event = create(:event, user: user)
    date_range = create(:date_range, event: event)

    result = described_class.call(
      event: event, user_id: user.id, date_range_id: date_range.id, vote_response: "invalid", comment: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid response value")
  end

  it "returns failure when date range not found" do
    user = create(:user)
    event = create(:event, user: user)

    result = described_class.call(
      event: event, user_id: user.id, date_range_id: "00000000-0000-0000-0000-000000000000", vote_response: "yes", comment: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range not found")
  end

  it "returns failure when date range belongs to different event" do
    user = create(:user)
    event1 = create(:event, user: user)
    event2 = create(:event, user: user)
    date_range = create(:date_range, event: event2)

    result = described_class.call(
      event: event1, user_id: user.id, date_range_id: date_range.id, vote_response: "yes", comment: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range does not belong to this event")
  end

  it "creates new vote and returns created: true" do
    user = create(:user)
    event = create(:event, user: user)
    date_range = create(:date_range, event: event)

    result = described_class.call(
      event: event,
      user_id: user.id,
      date_range_id: date_range.id,
      vote_response: "yes",
      comment: "Looks good!"
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:vote][:response]).to eq("yes")
    expect(result.value![:vote][:comment]).to eq("Looks good!")
  end

  it "updates existing vote and returns created: false" do
    user = create(:user)
    event = create(:event, user: user)
    date_range = create(:date_range, event: event)
    create(:vote, user: user, date_range: date_range, response: "yes")

    result = described_class.call(
      event: event,
      user_id: user.id,
      date_range_id: date_range.id,
      vote_response: "no",
      comment: "Changed my mind"
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be false
    expect(result.value![:vote][:response]).to eq("no")
    expect(Vote.count).to eq(1)
  end
end
