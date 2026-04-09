# frozen_string_literal: true

require "spec_helper"

RSpec.describe Votes::Delete do
  let(:workspace) { TestFactories.workspace }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when vote not found" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(event_id: event[:id], vote_id: "00000000-0000-0000-0000-000000000000", membership: membership_for(user))

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Vote not found")
    expect(result.failure.http_status).to eq(404)
  end

  it "returns failure when user is not the vote owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    vote = TestFactories.vote(user: owner, date_range: date_range)

    result = described_class.call(event_id: event[:id], vote_id: vote[:id], membership: membership_for(other_user))

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("not_creator")
    expect(result.failure.http_status).to eq(403)
  end

  it "returns failure when vote belongs to different event" do
    user = TestFactories.user
    event1 = TestFactories.event(workspace: workspace, user: user)
    event2 = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event2)
    date_range = TestFactories.date_range(date_poll: date_poll)
    vote = TestFactories.vote(user: user, date_range: date_range)

    result = described_class.call(event_id: event1[:id], vote_id: vote[:id], membership: membership_for(user))

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Vote does not belong to this event")
  end

  it "returns failure when poll is not open" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)
    vote = TestFactories.vote(user: user, date_range: date_range)

    result = described_class.call(event_id: event[:id], vote_id: vote[:id], membership: membership_for(user))

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not open for voting")
  end

  it "deletes vote and returns success" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    vote = TestFactories.vote(user: user, date_range: date_range)
    vote_id = vote[:id]

    result = described_class.call(event_id: event[:id], vote_id: vote[:id], membership: membership_for(user))

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "vote", id: vote_id }])
    expect(DB[:votes].where(id: vote_id).count).to eq(0)
  end
end
