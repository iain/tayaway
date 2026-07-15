# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsvps::Delete do
  let(:workspace) { TestFactories.workspace }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when RSVP not found" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(event_id: event[:id], rsvp_id: "00000000-0000-0000-0000-000000000000", membership: membership_for(user))

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("RSVP not found")
    expect(result.failure.http_status).to eq(404)
  end

  it "lets another workspace member delete an RSVP on the owner's behalf" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    rsvp = TestFactories.rsvp(event: event, user: owner)

    result = described_class.call(event_id: event[:id], rsvp_id: rsvp[:id], membership: membership_for(other_user))

    expect(result.success?).to be true
    expect(DB[:rsvps].where(id: rsvp[:id]).count).to eq(0)
  end

  it "returns failure when RSVP belongs to different event" do
    user = TestFactories.user
    event1 = TestFactories.event(workspace: workspace, user: user)
    event2 = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: event2[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    rsvp = TestFactories.rsvp(event: event2, user: user)

    result = described_class.call(event_id: event1[:id], rsvp_id: rsvp[:id], membership: membership_for(user))

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("RSVP does not belong to this event")
  end

  it "deletes RSVP and returns success" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    rsvp = TestFactories.rsvp(event: event, user: user)
    rsvp_id = rsvp[:id]

    result = described_class.call(event_id: event[:id], rsvp_id: rsvp[:id], membership: membership_for(user))

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "rsvp", id: rsvp_id }])
    expect(DB[:rsvps].where(id: rsvp_id).count).to eq(0)
  end

  it "reverts the mirrored member attendance to pending (dual-write, doc/attendances.md phase 2)" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    rsvp = TestFactories.rsvp(event: event, user: user, attendance: [Date.today])

    result = described_class.call(event_id: event[:id], rsvp_id: rsvp[:id], membership: membership_for(user))

    expect(result.success?).to be true
    row = DB[:attendances].where(event_id: event[:id], user_id: user[:id]).first
    expect(row[:status]).to eq("pending")
    expect(row[:days]).to be_nil
  end
end
