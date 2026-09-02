# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::AddDateRange do
  let(:workspace) { TestFactories.workspace }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(other_user),
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("not_event_owner")
  end

  # The poll's own payload carries its option list and the close permission
  # derived from it, so both go stale on other clients unless the poll moves
  # with the range.
  it "bumps and broadcasts the poll when an option is added" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    poll = DatePoll.find(TestFactories.date_poll(event: event)[:id])
    allow(Broadcaster).to receive(:object_changed).and_call_original

    described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(Broadcaster).to have_received(:object_changed).with("date_poll", poll.id)
    # The row carries a fresh trigger stamp rather than the one it was created
    # with. Not `be >`: specs run inside one transaction, and the trigger's
    # NOW() is the transaction's start time, not the statement's.
    expect(DatePoll.find(poll.id).updated_at).not_to eq(poll.updated_at)
  end

  it "returns failure when poll is not open" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event, closed_at: Time.now)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not open for changes")
  end

  it "returns failure when dates are invalid" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      start_date: "2024-06-10",
      end_date: "2024-06-01"
    )

    expect(result.failure?).to be true
  end

  it "adds a date range to the poll" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(result.success?).to be true
    date_range = result.value![:objects].find { |o| o[:objectType] == "dateRange" }
    expect(date_range).not_to be_nil
    expect(date_range[:datePollId]).to eq(date_poll[:id])
    expect(DB[:date_ranges].where(date_poll_id: date_poll[:id]).count).to eq(1)
  end

  it "uses client-provided id when given" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event)
    client_id = SecureRandom.uuid

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      start_date: "2024-06-01",
      end_date: "2024-06-10",
      id: client_id
    )

    expect(result.success?).to be true
    date_range = result.value![:objects].find { |o| o[:objectType] == "dateRange" }
    expect(date_range[:id]).to eq(client_id)
  end

  it "returns existing date range on idempotent replay with same id" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event)
    client_id = SecureRandom.uuid
    membership = membership_for(user)

    result1 = described_class.call(
      event_id: event[:id],
      membership: membership,
      start_date: "2024-06-01",
      end_date: "2024-06-10",
      id: client_id
    )
    result2 = described_class.call(
      event_id: event[:id],
      membership: membership,
      start_date: "2024-06-01",
      end_date: "2024-06-10",
      id: client_id
    )

    expect(result1.success?).to be true
    expect(result2.success?).to be true
    expect(DB[:date_ranges].where(id: client_id).count).to eq(1)
  end

  it "returns the existing date range when the client-provided id already exists" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event)
    client_id = SecureRandom.uuid

    TestFactories.date_range(id: client_id, date_poll: date_poll, start_date: Date.new(2024, 5, 1), end_date: Date.new(2024, 5, 3))

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      start_date: "2024-06-01",
      end_date: "2024-06-10",
      id: client_id
    )

    expect(result.success?).to be true
    date_range = result.value![:objects].find { |o| o[:objectType] == "dateRange" }
    expect(date_range[:id]).to eq(client_id)
    # Conflict is a no-op: original dates are preserved.
    expect(DB[:date_ranges].where(id: client_id).get(:start_date)).to eq(Date.new(2024, 5, 1))
    expect(DB[:date_ranges].where(id: client_id).count).to eq(1)
  end
end
