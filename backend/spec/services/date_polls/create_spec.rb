# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::Create do
  let(:workspace) { TestFactories.workspace }

  def membership_for(u)
    row = TestFactories.workspace_membership(workspace: workspace, user: u)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(other_user),
      deadline: (Time.now + 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("not_owner")
  end

  it "returns failure when a poll already exists" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: (Time.now + 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("A date poll already exists for this event")
  end

  it "returns failure when deadline is missing" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Deadline is required")
  end

  it "returns failure when deadline is in the past" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: (Time.now - 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Deadline must be in the future")
  end

  it "creates a date poll and returns success" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    deadline = (Time.now + 86_400).iso8601

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: deadline
    )

    expect(result.success?).to be true
    poll = result.value![:objects].find { |o| o[:objectType] == "datePoll" }
    expect(poll).not_to be_nil
    expect(poll[:eventId]).to eq(event[:id])
    expect(poll[:status]).to eq("open")
    event_obj = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event_obj[:datePollId]).to eq(poll[:id])
  end
end
