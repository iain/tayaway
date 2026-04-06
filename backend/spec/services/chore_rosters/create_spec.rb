# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::Create do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 7))
    DB[:events].where(id: e[:id]).first
  end

  let(:params) do
    { event_id: event[:id], user_id: user[:id], workspace_id: workspace[:id] }
  end

  it "creates a chore roster" do
    result = described_class.call(**params)

    expect(result.success?).to be true
    roster = result.value![:objects].find { |o| o[:objectType] == "choreRoster" }
    expect(roster[:eventId]).to eq(event[:id].to_s)
  end

  it "fails when event has no dates" do
    no_dates_event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(
      event_id: no_dates_event[:id],
      user_id: user[:id],
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to include("dates")
  end

  it "fails when a roster already exists" do
    described_class.call(**params)
    result = described_class.call(**params)

    expect(result.failure?).to be true
    expect(result.failure.message).to include("already exists")
  end

  it "creates a new roster when idempotent replay has mismatched event" do
    other_event = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: other_event[:id]).update(start_date: Date.new(2026, 4, 1), end_date: Date.new(2026, 4, 7))

    # Create a roster for the other event with a specific ID
    roster_id = SecureRandom.uuid
    described_class.call(
      event_id: other_event[:id],
      user_id: user[:id],
      workspace_id: workspace[:id],
      id: roster_id
    )

    # Now try to create a roster for our event with the same ID — should create a new one
    result = described_class.call(**params, id: roster_id)

    expect(result.success?).to be true
    roster = result.value![:objects].find { |o| o[:objectType] == "choreRoster" }
    expect(roster[:eventId]).to eq(event[:id].to_s)
    expect(roster[:id]).not_to eq(roster_id)
  end
end
