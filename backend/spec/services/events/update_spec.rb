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
      description: nil
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
      description: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "updates event name and description" do
    user = TestFactories.user
    event = TestFactories.event(user: user, name: "Original")

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Updated Name",
      description: "New description"
    )

    expect(result.success?).to be true
    updated_event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(updated_event[:name]).to eq("Updated Name")
    expect(updated_event[:description]).to eq("New description")
  end

  it "updates event with start and end dates" do
    user = TestFactories.user
    event = TestFactories.event(user: user, name: "Trip")

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Trip",
      description: nil,
      start_date: "2026-04-01",
      end_date: "2026-04-05"
    )

    expect(result.success?).to be true
    updated_event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(updated_event[:startDate]).to eq("2026-04-01")
    expect(updated_event[:endDate]).to eq("2026-04-05")
  end

  it "returns failure when only one date is provided" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Event",
      description: nil,
      start_date: "2026-04-01"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Both start date and end date must be provided")
  end

  it "returns failure when start_date is after end_date" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Event",
      description: nil,
      start_date: "2026-04-10",
      end_date: "2026-04-01"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Start date must be before or equal to end date")
  end
end
