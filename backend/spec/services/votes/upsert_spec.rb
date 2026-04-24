# frozen_string_literal: true

require "spec_helper"

RSpec.describe Votes::Upsert do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when date_range_id is missing" do
    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), date_range_id: nil, vote_response: "yes", comment: nil,
      vote_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("date_range_id is required")
  end

  it "returns failure when response is invalid" do
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), date_range_id: date_range[:id], vote_response: "invalid", comment: nil,
      vote_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid response value")
  end

  it "generates a server-side vote_id when none is provided" do
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), date_range_id: date_range[:id], vote_response: "yes", comment: nil,
      vote_id: nil
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:vote_id]).not_to be_nil
    expect(DB[:votes].count).to eq(1)
  end

  it "returns failure when date range not found" do
    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), date_range_id: "00000000-0000-0000-0000-000000000000", vote_response: "yes", comment: nil,
      vote_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range not found")
  end

  it "returns failure when date range belongs to different event" do
    event2 = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event2)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), date_range_id: date_range[:id], vote_response: "yes", comment: nil,
      vote_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range does not belong to this event")
  end

  it "returns failure when poll is not open" do
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), date_range_id: date_range[:id], vote_response: "yes", comment: nil,
      vote_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not open for voting")
  end

  it "creates new vote and returns created: true" do
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    client_id = SecureRandom.uuid

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      date_range_id: date_range[:id],
      vote_response: "yes",
      comment: "Looks good!",
      vote_id: client_id
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:vote_id].to_s).to eq(client_id)
    vote = DB[:votes].where(id: result.value![:vote_id]).first
    expect(vote[:response]).to eq("yes")
    expect(vote[:comment]).to eq("Looks good!")
  end

  it "uses client-provided vote_id for new vote" do
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    client_id = SecureRandom.uuid

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      date_range_id: date_range[:id],
      vote_response: "yes",
      comment: nil,
      vote_id: client_id
    )

    expect(result.success?).to be true
    expect(DB[:votes].where(id: client_id).count).to eq(1)
  end

  it "updates existing vote and returns created: false" do
    membership = membership_for(user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    TestFactories.vote(user: user, date_range: date_range, response: "yes")

    result = described_class.call(
      event_id: event[:id],
      membership: membership,
      date_range_id: date_range[:id],
      vote_response: "no",
      comment: "Changed my mind",
      vote_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be false
    vote = DB[:votes].where(id: result.value![:vote_id]).first
    expect(vote[:response]).to eq("no")
    expect(DB[:votes].count).to eq(1)
  end

  it "updates existing vote when called with the existing vote_id and changed values" do
    membership = membership_for(user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    client_id = SecureRandom.uuid

    described_class.call(
      event_id: event[:id],
      membership: membership,
      date_range_id: date_range[:id],
      vote_response: "yes",
      comment: nil,
      vote_id: client_id
    )
    result = described_class.call(
      event_id: event[:id],
      membership: membership,
      date_range_id: date_range[:id],
      vote_response: "no",
      comment: "Changed my mind",
      vote_id: client_id
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be false
    expect(result.value![:vote_id].to_s).to eq(client_id)
    vote = DB[:votes].where(id: client_id).first
    expect(vote[:response]).to eq("no")
    expect(vote[:comment]).to eq("Changed my mind")
    expect(DB[:votes].count).to eq(1)
  end

  it "returns existing vote on idempotent replay with same vote_id" do
    membership = membership_for(user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    client_id = SecureRandom.uuid

    result1 = described_class.call(
      event_id: event[:id],
      membership: membership,
      date_range_id: date_range[:id],
      vote_response: "yes",
      comment: nil,
      vote_id: client_id
    )
    result2 = described_class.call(
      event_id: event[:id],
      membership: membership,
      date_range_id: date_range[:id],
      vote_response: "yes",
      comment: nil,
      vote_id: client_id
    )

    expect(result1.success?).to be true
    expect(result1.value![:created]).to be true
    expect(result2.success?).to be true
    expect(result2.value![:created]).to be false
    expect(DB[:votes].where(id: client_id).count).to eq(1)
  end

  it "returns existing vote when a row already exists for this date_range+user under a different id" do
    membership = membership_for(user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    existing_id = SecureRandom.uuid
    TestFactories.vote(id: existing_id, user: user, date_range: date_range, response: "yes")

    # Client sends a new id but date_range+user already has a vote — ON CONFLICT updates
    # the existing row and returns its id.
    result = described_class.call(
      event_id: event[:id],
      membership: membership,
      date_range_id: date_range[:id],
      vote_response: "no",
      comment: nil,
      vote_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    expect(result.value![:vote_id].to_s).to eq(existing_id)
    expect(DB[:votes].where(id: existing_id).get(:response)).to eq("no")
    expect(DB[:votes].count).to eq(1)
  end
end
