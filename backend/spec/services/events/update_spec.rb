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

  it "returns failure when clearing dates while a resolved poll exists" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event, closed_at: Time.now)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Event",
      description: nil,
      start_date: "",
      end_date: ""
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Cannot clear dates while a resolved poll exists")
    expect(result.failure.http_status).to eq(400)
  end

  it "allows clearing dates when no poll exists" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Event",
      description: nil,
      start_date: "",
      end_date: ""
    )

    expect(result.success?).to be true
    updated_event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(updated_event[:startDate]).to be_nil
    expect(updated_event[:endDate]).to be_nil
  end

  it "allows clearing dates when an open poll exists" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event, deadline: Time.now + (7 * 24 * 60 * 60))

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Event",
      description: nil,
      start_date: "",
      end_date: ""
    )

    expect(result.success?).to be true
    updated_event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(updated_event[:startDate]).to be_nil
    expect(updated_event[:endDate]).to be_nil
  end

  it "sets location_name without coordinates" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Event",
      description: nil,
      location_name: "Somewhere Nice"
    )

    expect(result.success?).to be true
    updated_event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(updated_event[:locationName]).to eq("Somewhere Nice")
    expect(updated_event[:latitude]).to be_nil
    expect(updated_event[:longitude]).to be_nil
  end

  it "sets location_name with coordinates" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Event",
      description: nil,
      location_name: "Eiffel Tower",
      latitude: 48.8584,
      longitude: 2.2945
    )

    expect(result.success?).to be true
    updated_event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(updated_event[:locationName]).to eq("Eiffel Tower")
    expect(updated_event[:latitude]).to be_within(0.001).of(48.8584)
    expect(updated_event[:longitude]).to be_within(0.001).of(2.2945)
  end

  it "logs info when event is updated" do
    user = TestFactories.user
    event = TestFactories.event(user: user, name: "Original")
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(event_id: event[:id], current_user_id: user[:id], name: "Updated", description: nil)

    expect(logged_messages).to include(a_string_including("[Events::Update]"))
  end

  it "clears location when location_name is empty" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    # First set a location
    described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Event",
      description: nil,
      location_name: "Somewhere Nice",
      latitude: 48.8584,
      longitude: 2.2945
    )

    # Then clear it
    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      name: "Event",
      description: nil,
      location_name: ""
    )

    expect(result.success?).to be true
    updated_event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(updated_event[:locationName]).to be_nil
    expect(updated_event[:latitude]).to be_nil
    expect(updated_event[:longitude]).to be_nil
  end
end
