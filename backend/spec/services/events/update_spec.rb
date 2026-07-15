# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Update do
  let(:workspace) { TestFactories.workspace }

  def membership_for(user)
    row = TestFactories.workspace_membership(workspace: workspace, user: user)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when user is not the owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    membership_for(owner)
    other_membership = membership_for(other_user)
    event = TestFactories.event(workspace: workspace, user: owner)

    result = described_class.call(
      event_id: event[:id],
      membership: other_membership,
      name: "Updated",
      description: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to include("not_owner")
    expect(result.failure.http_status).to eq(403)
  end

  it "returns failure when name is missing" do
    user = TestFactories.user
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
      name: "",
      description: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "updates event name and description" do
    user = TestFactories.user
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user, name: "Original")

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
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
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user, name: "Trip")

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
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
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
      name: "Event",
      description: nil,
      start_date: "2026-04-01"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Both start date and end date must be provided")
  end

  it "returns failure when start_date is after end_date" do
    user = TestFactories.user
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
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
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event, closed_at: Time.now)

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
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
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
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
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event, deadline: Time.now + (7 * 24 * 60 * 60))

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
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
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
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
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
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
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user, name: "Original")
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(event_id: event[:id], membership: membership, name: "Updated", description: nil)

    expect(logged_messages).to include(a_string_including("[Events::Update]"))
  end

  it "clears location when location_name is empty" do
    user = TestFactories.user
    membership = membership_for(user)
    event = TestFactories.event(workspace: workspace, user: user)

    # First set a location
    described_class.call(
      event_id: event[:id],
      membership: membership,
      name: "Event",
      description: nil,
      location_name: "Somewhere Nice",
      latitude: 48.8584,
      longitude: 2.2945
    )

    # Then clear it
    result = described_class.call(
      event_id: event[:id],
      membership: membership,
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

  describe "date-change reset (doc/attendances.md phase 6)" do
    def update_dates(event, membership, start_date, end_date)
      described_class.call(
        event_id: event[:id], membership: membership,
        name: "Trip", description: nil,
        start_date: start_date.iso8601, end_date: end_date.iso8601
      )
    end

    it "keeps the people and clears the answers when dates change" do
      owner = TestFactories.user
      membership = membership_for(owner)
      event = TestFactories.event(workspace: workspace, user: owner)
      DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 3)
      rsvp = TestFactories.rsvp(event: event, user: owner, attendance: [Date.today])
      guest = TestFactories.guest(workspace: workspace)
      guest_row = TestFactories.attendance(event: event, guest: guest, host: owner, days: [Date.today])

      result = update_dates(event, membership, Date.today + 10, Date.today + 13)

      expect(result.success?).to be true
      rows = DB[:attendances].where(event_id: event[:id]).all
      expect(rows.length).to eq(2)
      expect(rows.map { |r| r[:status] }).to all(eq("pending"))
      expect(rows.map { |r| r[:days] }).to all(be_nil)
      expect(rows.map { |r| r[:id] }).to include(guest_row[:id])
      # Legacy rsvp rows are deleted for stale clients (row absence is their
      # "no response"), with tombstones so their pools drop the rows too.
      expect(DB[:rsvps].where(id: rsvp[:id]).count).to eq(0)
      expect(DB[:deleted_items].where(object_type: "rsvp", object_id: rsvp[:id]).count).to eq(1)
      expect(result.value![:deleted]).to include({ objectType: "rsvp", id: rsvp[:id] })
    end

    it "notifies the people who had answered, resolved before the revert" do
      owner = TestFactories.user
      attendee = TestFactories.user
      membership = membership_for(owner)
      membership_for(attendee)
      event = TestFactories.event(workspace: workspace, user: owner)
      DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 3)
      TestFactories.rsvp(event: event, user: attendee, attending: true)

      update_dates(event, membership, Date.today + 10, Date.today + 13)

      expect(DB[:notifications].where(user_id: attendee[:id], kind: "event_details_changed").count).to eq(1)
      expect(DB[:attendances].where(event_id: event[:id], user_id: attendee[:id]).get(:status)).to eq("pending")
    end

    it "does not reset when dates are set for the first time or unchanged" do
      owner = TestFactories.user
      membership = membership_for(owner)
      event = TestFactories.event(workspace: workspace, user: owner)

      first_set = update_dates(event, membership, Date.today, Date.today + 3)
      expect(first_set.success?).to be true

      TestFactories.rsvp(event: event, user: owner, attending: true)
      unchanged = update_dates(event, membership, Date.today, Date.today + 3)

      expect(unchanged.success?).to be true
      expect(DB[:attendances].where(event_id: event[:id]).get(:status)).to eq("going")
      expect(DB[:rsvps].where(event_id: event[:id]).count).to eq(1)
    end
  end
end
