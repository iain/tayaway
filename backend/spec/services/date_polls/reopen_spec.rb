# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::Reopen do
  let(:workspace) { TestFactories.workspace }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: owner)
    TestFactories.date_poll(event: event, closed_at: Time.now)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(other_user),
      deadline: (Time.now + 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("not_event_owner")
  end

  it "returns failure when poll is not resolved" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: (Time.now + 86_400).iso8601
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not resolved")
  end

  it "returns failure when deadline is missing" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event, closed_at: Time.now)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Deadline is required")
  end

  it "reopens the poll with a new deadline" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)
    DB[:date_polls].where(id: date_poll[:id]).update(selected_date_range_id: date_range[:id])
    new_deadline = (Time.now + 86_400).iso8601

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: new_deadline
    )

    expect(result.success?).to be true
    poll = result.value![:objects].find { |o| o[:objectType] == "datePoll" }
    expect(poll[:status]).to eq("open")
    expect(poll[:selectedDateRangeId]).to be_nil

    db_poll = DB[:date_polls].where(id: date_poll[:id]).first
    expect(db_poll[:closed_at]).to be_nil
    expect(db_poll[:selected_date_range_id]).to be_nil
  end

  it "logs info when poll is reopened" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event, closed_at: Time.now)
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: (Time.now + 86_400).iso8601
    )

    expect(logged_messages).to include(a_string_including("[DatePolls::Reopen]"))
  end

  it "deletes all RSVPs when reopening" do
    user = TestFactories.user
    voter = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    date_poll = TestFactories.date_poll(event: event, closed_at: Time.now)
    date_range = TestFactories.date_range(date_poll: date_poll)
    DB[:date_polls].where(id: date_poll[:id]).update(selected_date_range_id: date_range[:id])
    DB[:events].where(id: event[:id]).update(start_date: date_range[:start_date], end_date: date_range[:end_date])

    rsvp = TestFactories.rsvp(event: event, user: voter)
    new_deadline = (Time.now + 86_400).iso8601

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: new_deadline
    )

    expect(result.success?).to be true
    expect(DB[:rsvps].where(event_id: event[:id]).count).to eq(0)
    expect(result.value![:deleted]).to include({ objectType: "rsvp", id: rsvp[:id] })
  end

  it "reverts the event's attendances to pending (dual-write, doc/attendances.md phase 2)" do
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    TestFactories.date_poll(event: event, closed_at: Time.now)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 3)
    TestFactories.rsvp(event: event, user: user, attending: true)
    member_row = TestFactories.attendance(event: event, user: user, status: "going", days: [Date.today])
    guest = TestFactories.guest(workspace: workspace)
    guest_row = TestFactories.attendance(event: event, guest: guest, host: user, status: "going")

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      deadline: (Time.now + 86_400).iso8601
    )

    expect(result.success?).to be true
    [member_row, guest_row].each do |row|
      reverted = DB[:attendances].where(id: row[:id]).first
      expect(reverted[:status]).to eq("pending")
      expect(reverted[:days]).to be_nil
    end
  end
end
