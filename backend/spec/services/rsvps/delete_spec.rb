# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsvps::Delete do
  it "returns failure when RSVP not found" do
    user = TestFactories.user
    event = TestFactories.event(user: user)

    result = described_class.call(event_id: event[:id], rsvp_id: "00000000-0000-0000-0000-000000000000", user_id: user[:id])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("RSVP not found")
    expect(result.failure.http_status).to eq(404)
  end

  it "returns failure when user is not the RSVP owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(user: owner)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    rsvp = TestFactories.rsvp(event: event, user: owner)

    result = described_class.call(event_id: event[:id], rsvp_id: rsvp[:id], user_id: other_user[:id])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
    expect(result.failure.http_status).to eq(403)
  end

  it "returns failure when RSVP belongs to different event" do
    user = TestFactories.user
    event1 = TestFactories.event(user: user)
    event2 = TestFactories.event(user: user)
    DB[:events].where(id: event2[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    rsvp = TestFactories.rsvp(event: event2, user: user)

    result = described_class.call(event_id: event1[:id], rsvp_id: rsvp[:id], user_id: user[:id])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("RSVP does not belong to this event")
  end

  it "deletes RSVP and returns success" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    rsvp = TestFactories.rsvp(event: event, user: user)
    rsvp_id = rsvp[:id]

    result = described_class.call(event_id: event[:id], rsvp_id: rsvp[:id], user_id: user[:id])

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "rsvp", id: rsvp_id }])
    expect(DB[:rsvps].where(id: rsvp_id).count).to eq(0)
  end
end
