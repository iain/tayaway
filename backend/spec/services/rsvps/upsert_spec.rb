# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsvps::Upsert do
  it "returns failure when attending is nil" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("attending is required")
  end

  it "returns failure when event not found" do
    user = TestFactories.user

    result = described_class.call(
      event_id: "00000000-0000-0000-0000-000000000000",
      user_id: user[:id],
      attending: true
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Event not found")
  end

  it "returns failure when event has no dates set" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: true)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Event does not have dates set")
  end

  it "creates an RSVP when event has dates" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(event_id: event[:id], user_id: user[:id], attending: true)

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be true
    expect(rsvp[:start_date]).to be_nil
    expect(rsvp[:end_date]).to be_nil
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
      end_date: (Date.today + 3).iso8601
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
      end_date: (Date.today + 3).iso8601
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
      end_date: (Date.today + 3).iso8601
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

    result1 = described_class.call(event_id: event[:id], user_id: user[:id], attending: true)
    expect(result1.value![:created]).to be true

    result2 = described_class.call(event_id: event[:id], user_id: user[:id], attending: false)
    expect(result2.success?).to be true
    expect(result2.value![:created]).to be false

    rsvp = DB[:rsvps].where(id: result2.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be false
    expect(DB[:rsvps].count).to eq(1)
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
end
