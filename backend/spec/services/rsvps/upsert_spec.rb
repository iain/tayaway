# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsvps::Upsert do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when attending is nil" do
    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: nil, rsvp_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("attending is required")
  end

  it "generates a server-side rsvp_id when none is provided" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: true, rsvp_id: nil)

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:rsvp_id]).not_to be_nil
    expect(DB[:rsvps].count).to eq(1)
  end

  it "returns failure when event not found" do
    result = described_class.call(
      event_id: "00000000-0000-0000-0000-000000000000",
      membership: membership_for(user),
      user_id: user[:id],
      attending: true,
      rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Event not found")
  end

  it "returns failure when event has no dates set" do
    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Event does not have dates set")
  end

  it "creates an RSVP when event has dates" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: true, rsvp_id: client_id)

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:rsvp_id].to_s).to eq(client_id)
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be true
    expect(rsvp[:start_date]).to be_nil
    expect(rsvp[:end_date]).to be_nil
  end

  it "uses client-provided rsvp_id for new RSVP" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: true, rsvp_id: client_id)

    expect(result.success?).to be true
    expect(DB[:rsvps].where(id: client_id).count).to eq(1)
  end

  it "creates an RSVP with partial dates" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
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
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
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
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
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
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result1 = described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)
    expect(result1.value![:created]).to be true

    result2 = described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid)
    expect(result2.success?).to be true
    expect(result2.value![:created]).to be false

    rsvp = DB[:rsvps].where(id: result2.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be false
    expect(DB[:rsvps].count).to eq(1)
  end

  it "returns failure when declining with expenses on the event" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    # RSVP as attending first
    described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)

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

    result = described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("You cannot decline while you have expenses on this event")
    expect(result.failure.http_status).to eq(403)
  end

  it "allows declining when user has no expenses on the event" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)

    result = described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid)

    expect(result.success?).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be false
  end

  it "updates existing RSVP when called with the existing rsvp_id and changed values" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: client_id
    )
    result = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: client_id
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be false
    expect(result.value![:rsvp_id].to_s).to eq(client_id)
    rsvp = DB[:rsvps].where(id: client_id).first
    expect(rsvp[:attending]).to be false
    expect(DB[:rsvps].count).to eq(1)
  end

  it "returns existing RSVP on idempotent replay with same rsvp_id" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    result1 = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: client_id
    )
    result2 = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: client_id
    )

    expect(result1.success?).to be true
    expect(result1.value![:created]).to be true
    expect(result2.success?).to be true
    expect(result2.value![:created]).to be false
    expect(DB[:rsvps].where(id: client_id).count).to eq(1)
  end

  it "lets a workspace member RSVP on behalf of another member" do
    other = TestFactories.user
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    actor_membership = membership_for(user)
    membership_for(other) # ensure subject is a workspace member

    result = described_class.call(
      event_id: event[:id], membership: actor_membership, user_id: other[:id], attending: true, rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:user_id]).to eq(other[:id])
  end

  it "returns failure when subject is not a workspace member" do
    stranger = TestFactories.user
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: stranger[:id], attending: true, rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("User is not a member of this workspace")
  end

  it "returns failure when user_id is missing" do
    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: nil, attending: true, rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("user_id is required")
  end

  it "returns existing RSVP when a row already exists for this event+user under a different id" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    existing_id = SecureRandom.uuid
    TestFactories.rsvp(id: existing_id, event: event, user: user, attending: true)

    # Client sends a new id but event+user already has an RSVP — ON CONFLICT updates
    # the existing row and returns its id.
    result = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    expect(result.value![:rsvp_id].to_s).to eq(existing_id)
    expect(result.value![:created]).to be false
    expect(DB[:rsvps].where(id: existing_id).get(:attending)).to be false
    expect(DB[:rsvps].count).to eq(1)
  end
end
