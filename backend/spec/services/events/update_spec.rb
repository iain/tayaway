# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Update do
  it "returns failure when user is not the owner" do
    owner = create(:user)
    other_user = create(:user)
    event = create(:event, user: owner)

    result = described_class.call(
      event: event,
      current_user_id: other_user.id,
      name: "Updated",
      description: nil,
      date_ranges: []
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
    expect(result.failure.http_status).to eq(403)
  end

  it "returns failure when name is missing" do
    user = create(:user)
    event = create(:event, user: user)

    result = described_class.call(
      event: event,
      current_user_id: user.id,
      name: "",
      description: nil,
      date_ranges: []
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "updates event and replaces date ranges" do
    user = create(:user)
    event = create(:event, user: user, name: "Original")
    create(:date_range, event: event)
    new_date_ranges = [{ "start_date" => "2024-06-01", "end_date" => "2024-06-10" }]

    result = described_class.call(
      event: event,
      current_user_id: user.id,
      name: "Updated Name",
      description: "New description",
      date_ranges: new_date_ranges
    )

    expect(result.success?).to be true
    expect(result.value![:event][:name]).to eq("Updated Name")
    expect(result.value![:event][:date_ranges].length).to eq(1)
    expect(DateRange.where(event_id: event.id).count).to eq(1)
  end

  it "preserves votes on unchanged date ranges" do
    user = create(:user)
    voter = create(:user)
    event = create(:event, user: user)
    date_range = create(:date_range, event: event, start_date: Date.new(2024, 6, 1), end_date: Date.new(2024, 6, 10))
    vote = create(:vote, date_range: date_range, user: voter, response: "yes")

    result = described_class.call(
      event: event,
      current_user_id: user.id,
      name: "Updated Name",
      description: nil,
      date_ranges: [
        { "start_date" => "2024-06-01", "end_date" => "2024-06-10" },
        { "start_date" => "2024-07-01", "end_date" => "2024-07-05" }
      ]
    )

    expect(result.success?).to be true
    expect(Vote.where(id: vote.id).count).to eq(1)
    expect(DateRange.where(event_id: event.id).count).to eq(2)
  end

  it "deletes votes when their date range is removed" do
    user = create(:user)
    voter = create(:user)
    event = create(:event, user: user)
    kept_range = create(:date_range, event: event, start_date: Date.new(2024, 6, 1), end_date: Date.new(2024, 6, 10))
    removed_range = create(:date_range, event: event, start_date: Date.new(2024, 7, 1), end_date: Date.new(2024, 7, 10))
    kept_vote = create(:vote, date_range: kept_range, user: voter)
    removed_vote = create(:vote, date_range: removed_range, user: voter)

    result = described_class.call(
      event: event,
      current_user_id: user.id,
      name: "Updated",
      description: nil,
      date_ranges: [{ "start_date" => "2024-06-01", "end_date" => "2024-06-10" }]
    )

    expect(result.success?).to be true
    expect(Vote.where(id: kept_vote.id).count).to eq(1)
    expect(Vote.where(id: removed_vote.id).count).to eq(0)
  end
end
