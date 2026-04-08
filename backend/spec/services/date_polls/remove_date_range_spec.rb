# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::RemoveDateRange do
  let(:workspace) { TestFactories.workspace }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(other_user),
      date_range_id: date_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("not_owner")
  end

  it "returns failure when poll is not open" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      date_range_id: date_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not open for changes")
  end

  it "returns failure when date range does not belong to poll" do
    user = TestFactories.user
    event1 = TestFactories.event(workspace: workspace, user: user)
    event2 = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event1)
    other_poll = TestFactories.date_poll(event: event2)
    other_range = TestFactories.date_range(date_poll: other_poll)

    result = described_class.call(
      event_id: event1[:id],
      membership: membership_for(user),
      date_range_id: other_range[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Date range does not belong to this poll")
  end

  it "removes a date range from the poll" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event)
    date_range = TestFactories.date_range(date_poll: date_poll)
    dr_id = date_range[:id]

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      date_range_id: dr_id
    )

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "dateRange", id: dr_id }])
    expect(DB[:date_ranges].where(id: dr_id).count).to eq(0)
  end
end
