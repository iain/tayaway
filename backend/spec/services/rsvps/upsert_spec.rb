# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsvps::Upsert do
  it "returns failure when attending is nil" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: nil, rsvp_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("attending is required")
  end

  it "generates a server-side rsvp_id when none is provided" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: nil)

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:rsvp_id]).not_to be_nil
    expect(DB[:rsvps].count).to eq(1)
  end

  it "returns failure when event not found" do
    user = TestFactories.user

    result = described_class.call(
      event_id: "00000000-0000-0000-0000-000000000000",
      user_id: user[:id],
      attending: true,
      rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Event not found")
  end

  it "returns failure when event has no dates set" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Event does not have dates set")
  end

  it "creates an RSVP when event has dates" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: client_id)

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:rsvp_id].to_s).to eq(client_id)
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be true
    expect(rsvp[:start_date]).to be_nil
    expect(rsvp[:end_date]).to be_nil
  end

  it "uses client-provided rsvp_id for new RSVP" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: client_id)

    expect(result.success?).to be true
    expect(DB[:rsvps].where(id: client_id).count).to eq(1)
  end

  it "creates an RSVP with partial dates" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id],
      user_id: user[:id],
      attending: true,
      start_date: (Date.today + 1).iso8601,
      end_date: (Date.today + 3).iso8601,
      rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be true
    expect(rsvp[:start_date]).to eq(Date.today + 1)
    expect(rsvp[:end_date]).to eq(Date.today + 3)
  end

  it "returns failure when partial dates are outside event range" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id],
      user_id: user[:id],
      attending: true,
      start_date: (Date.today - 1).iso8601,
      end_date: (Date.today + 3).iso8601,
      rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Partial dates must fall within the event date range")
  end

  it "clears partial dates when not attending" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id],
      user_id: user[:id],
      attending: false,
      start_date: (Date.today + 1).iso8601,
      end_date: (Date.today + 3).iso8601,
      rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be false
    expect(rsvp[:start_date]).to be_nil
    expect(rsvp[:end_date]).to be_nil
  end

  it "updates existing RSVP and returns created: false" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result1 = described_class.call(event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)
    expect(result1.value![:created]).to be true

    result2 = described_class.call(event_id: event[:id], user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid)
    expect(result2.success?).to be true
    expect(result2.value![:created]).to be false

    rsvp = DB[:rsvps].where(id: result2.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be false
    expect(DB[:rsvps].count).to eq(1)
  end

  it "returns failure when declining with expenses on the event" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    # RSVP as attending first
    described_class.call(event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)

    # Create an expense on this event
    now = Time.now
    DB[:expenses].insert(
      id: SecureRandom.uuid,
      event_id: event[:id],
      user_id: user[:id],
      amount: 50,
      description: "Dinner",
      start_date: Date.today,
      end_date: Date.today + 1,
      created_at: now,
      updated_at: now
    )

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("You cannot decline while you have expenses on this event")
    expect(result.failure.http_status).to eq(403)
  end

  it "allows declining when user has no expenses on the event" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    described_class.call(event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid)

    expect(result.success?).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be false
  end

  it "returns existing RSVP on idempotent replay with same rsvp_id" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    result1 = described_class.call(
      event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: client_id
    )
    result2 = described_class.call(
      event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: client_id
    )

    expect(result1.success?).to be true
    expect(result1.value![:created]).to be true
    expect(result2.success?).to be true
    expect(result2.value![:created]).to be false
    expect(DB[:rsvps].where(id: client_id).count).to eq(1)
  end

  it "handles TOCTOU race: returns existing RSVP when concurrent insert wins" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    # Pre-insert an RSVP with this ID (simulates concurrent request that won the race)
    TestFactories.rsvp(id: client_id, event: event, user: user, attending: true)

    existing_rsvp = Rsvp.find(client_id)

    # Simulate the TOCTOU race: the early idempotency check sees nil (the race window).
    # find_by_event_and_user also returns nil so the service attempts an insert, hits
    # UniqueConstraintViolation, and rescues by re-fetching the winner.
    allow(Rsvp).to receive(:find).with(client_id).and_return(nil)
    allow(Rsvp).to receive(:find_by_event_and_user).and_return(nil, existing_rsvp)

    result = described_class.call(
      event_id: event[:id], user_id: user[:id], attending: true, rsvp_id: client_id
    )

    expect(result.success?).to be true
    expect(result.value![:rsvp_id].to_s).to eq(client_id)
    expect(result.value![:created]).to be false
    expect(DB[:rsvps].count).to eq(1)
  end
end
