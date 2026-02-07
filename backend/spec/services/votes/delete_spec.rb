# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Votes::Delete do
  it "returns failure when vote not found" do
    user = create(:user)
    event = create(:event, user: user)

    result = described_class.call(event_id: event[:id], vote_id: "00000000-0000-0000-0000-000000000000", user_id: user[:id])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Vote not found")
    expect(result.failure.http_status).to eq(404)
  end

  it "returns failure when user is not the vote owner" do
    owner = create(:user)
    other_user = create(:user)
    event = create(:event, user: owner)
    date_range = create(:date_range, event: event)
    vote = create(:vote, user: owner, date_range: date_range)

    result = described_class.call(event_id: event[:id], vote_id: vote[:id], user_id: other_user[:id])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
    expect(result.failure.http_status).to eq(403)
  end

  it "returns failure when vote belongs to different event" do
    user = create(:user)
    event1 = create(:event, user: user)
    event2 = create(:event, user: user)
    date_range = create(:date_range, event: event2)
    vote = create(:vote, user: user, date_range: date_range)

    result = described_class.call(event_id: event1[:id], vote_id: vote[:id], user_id: user[:id])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Vote does not belong to this event")
  end

  it "deletes vote and returns success" do
    user = create(:user)
    event = create(:event, user: user)
    date_range = create(:date_range, event: event)
    vote = create(:vote, user: user, date_range: date_range)
    vote_id = vote[:id]

    result = described_class.call(event_id: event[:id], vote_id: vote[:id], user_id: user[:id])

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "vote", id: vote_id }])
    expect(DB[:votes].where(id: vote_id).count).to eq(0)
  end
end
