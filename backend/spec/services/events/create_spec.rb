# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Create do
  def membership_for(user, workspace)
    row = TestFactories.workspace_membership(workspace: workspace, user: user)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when name is missing" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(workspace_id: workspace[:id], membership: membership, name: nil, description: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "creates event and returns success" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(
      workspace_id: workspace[:id],
      membership: membership,
      name: "Team Meeting",
      description: "Weekly sync"
    )

    expect(result.success?).to be true
    event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event[:name]).to eq("Team Meeting")
    expect(event[:description]).to eq("Weekly sync")
    expect(event[:datePollId]).to be_nil
  end

  it "sets description to nil when empty" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(workspace_id: workspace[:id], membership: membership, name: "Event", description: "")

    expect(result.success?).to be true
    event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event[:description]).to be_nil
  end

  it "uses client-provided id when given" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)
    client_id = SecureRandom.uuid

    result = described_class.call(
      workspace_id: workspace[:id], membership: membership, name: "Test", description: nil, id: client_id
    )

    expect(result.success?).to be true
    event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event[:id]).to eq(client_id)
  end

  it "creates event with start and end dates" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(
      workspace_id: workspace[:id],
      membership: membership,
      name: "Holiday Trip",
      description: nil,
      start_date: "2026-03-15",
      end_date: "2026-03-20"
    )

    expect(result.success?).to be true
    event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event[:startDate]).to eq("2026-03-15")
    expect(event[:endDate]).to eq("2026-03-20")
  end

  it "returns failure when only start_date is provided" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(
      workspace_id: workspace[:id],
      membership: membership,
      name: "Event",
      description: nil,
      start_date: "2026-03-15"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Both start date and end date must be provided")
  end

  it "returns failure when only end_date is provided" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(
      workspace_id: workspace[:id],
      membership: membership,
      name: "Event",
      description: nil,
      end_date: "2026-03-20"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Both start date and end date must be provided")
  end

  it "returns failure when start_date is after end_date" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(
      workspace_id: workspace[:id],
      membership: membership,
      name: "Event",
      description: nil,
      start_date: "2026-03-20",
      end_date: "2026-03-15"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Start date must be before or equal to end date")
  end

  it "logs info when event is created" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(workspace_id: workspace[:id], membership: membership, name: "Party", description: nil)

    expect(logged_messages).to include(a_string_including("[Events::Create]"))
  end

  it "returns existing event on idempotent replay with same id" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)
    client_id = SecureRandom.uuid

    result1 = described_class.call(
      workspace_id: workspace[:id], membership: membership, name: "Test", description: nil, id: client_id
    )
    result2 = described_class.call(
      workspace_id: workspace[:id], membership: membership, name: "Test", description: nil, id: client_id
    )

    expect(result1.success?).to be true
    expect(result2.success?).to be true
    expect(DB[:events].where(id: client_id).count).to eq(1)
  end

  it "creates event with valid coordinates" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(
      workspace_id: workspace[:id],
      membership: membership,
      name: "Located Event",
      description: nil,
      location_name: "Berlin",
      latitude: 52.52,
      longitude: 13.405
    )

    expect(result.success?).to be true
    event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event[:locationName]).to eq("Berlin")
  end

  it "returns failure when latitude is out of range" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(
      workspace_id: workspace[:id],
      membership: membership,
      name: "Event",
      description: nil,
      location_name: "Nowhere",
      latitude: 91.0,
      longitude: 0.0
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Latitude must be between -90 and 90")
  end

  it "returns failure when longitude is out of range" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)

    result = described_class.call(
      workspace_id: workspace[:id],
      membership: membership,
      name: "Event",
      description: nil,
      location_name: "Nowhere",
      latitude: 0.0,
      longitude: -181.0
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Longitude must be between -180 and 180")
  end

  it "handles TOCTOU race: returns existing event when concurrent insert wins" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership = membership_for(user, workspace)
    client_id = SecureRandom.uuid

    # Pre-insert an event with this ID (simulates concurrent request that won the race)
    TestFactories.event(id: client_id, user: user, workspace: workspace, name: "Test")
    existing_event = Event.find(client_id)

    # Simulate the TOCTOU race: the early idempotency check sees nil (the race window),
    # so the service proceeds to insert and hits UniqueConstraintViolation.
    allow(Event).to receive(:find).with(client_id).and_return(nil, existing_event)

    result = described_class.call(
      workspace_id: workspace[:id], membership: membership, name: "Test", description: nil, id: client_id
    )

    expect(result.success?).to be true
    event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event[:id]).to eq(client_id)
    expect(DB[:events].where(id: client_id).count).to eq(1)
  end
end
