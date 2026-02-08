# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Update do
  it "returns failure when user is not the owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(user: owner)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: other_user[:id],
      name: "Updated",
      description: nil,
      date_ranges: []
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
    expect(result.failure.http_status).to eq(403)
  end

  it "returns failure when name is missing" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "",
      description: nil,
      date_ranges: []
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "updates event and replaces date ranges" do
    user = TestFactories.user
    event = TestFactories.event(user: user, name: "Original")
    TestFactories.date_range(event: event)
    new_date_ranges = [{ "start_date" => "2024-06-01", "end_date" => "2024-06-10" }]

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Updated Name",
      description: "New description",
      date_ranges: new_date_ranges
    )

    expect(result.success?).to be true
    updated_event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(updated_event[:name]).to eq("Updated Name")
    expect(updated_event[:dateRangeIds].length).to eq(1)
    expect(DB[:date_ranges].where(event_id: event[:id]).count).to eq(1)
  end

  it "preserves votes on unchanged date ranges" do
    user = TestFactories.user
    voter = TestFactories.user
    event = TestFactories.event(user: user)
    date_range = TestFactories.date_range(event: event, start_date: Date.new(2024, 6, 1), end_date: Date.new(2024, 6, 10))
    vote = TestFactories.vote(date_range: date_range, user: voter, response: "yes")

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Updated Name",
      description: nil,
      date_ranges: [
        { "start_date" => "2024-06-01", "end_date" => "2024-06-10" },
        { "start_date" => "2024-07-01", "end_date" => "2024-07-05" }
      ]
    )

    expect(result.success?).to be true
    expect(DB[:votes].where(id: vote[:id]).count).to eq(1)
    expect(DB[:date_ranges].where(event_id: event[:id]).count).to eq(2)
  end

  it "deletes votes when their date range is removed" do
    user = TestFactories.user
    voter = TestFactories.user
    event = TestFactories.event(user: user)
    kept_range = TestFactories.date_range(event: event, start_date: Date.new(2024, 6, 1), end_date: Date.new(2024, 6, 10))
    removed_range = TestFactories.date_range(event: event, start_date: Date.new(2024, 7, 1), end_date: Date.new(2024, 7, 10))
    kept_vote = TestFactories.vote(date_range: kept_range, user: voter)
    removed_vote = TestFactories.vote(date_range: removed_range, user: voter)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Updated",
      description: nil,
      date_ranges: [{ "start_date" => "2024-06-01", "end_date" => "2024-06-10" }]
    )

    expect(result.success?).to be true
    expect(DB[:votes].where(id: kept_vote[:id]).count).to eq(1)
    expect(DB[:votes].where(id: removed_vote[:id]).count).to eq(0)
  end
end
