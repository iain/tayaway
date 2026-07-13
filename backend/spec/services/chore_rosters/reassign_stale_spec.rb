# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::ReassignStale do
  let(:user_a) { TestFactories.user(name: "Alice") }
  let(:user_b) { TestFactories.user(name: "Bob") }
  let(:user_c) { TestFactories.user(name: "Charlie") }
  let(:workspace) { TestFactories.workspace }
  let(:event_start) { Date.new(2026, 3, 1) }
  let(:event_end) { Date.new(2026, 3, 4) }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user_a)
    DB[:events].where(id: e[:id]).update(start_date: event_start, end_date: event_end)
    DB[:events].where(id: e[:id]).first
  end
  let(:roster) { TestFactories.chore_roster(event: event, user: user_a) }

  before { allow(Timezones).to receive(:today).and_return(Date.new(2026, 3, 1)) }

  def membership_for(usr)
    existing = DB[:workspace_memberships].where(workspace_id: workspace[:id], user_id: usr[:id]).first
    row = existing || TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  define_method(:create_rsvp) do |user, start_date: nil, end_date: nil|
    TestFactories.rsvp(event: event, user: user, attending: true, start_date: start_date, end_date: end_date)
  end

  it "hands a stale assignment to an attendee, keeping the row in place" do
    # Alice left after day 1 but still holds day 3; Bob is around all event.
    create_rsvp(user_a, start_date: event_start, end_date: event_start)
    create_rsvp(user_b)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
    stale = TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 3), pinned: false)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_b))
    expect(result.success?).to be true

    row = DB[:chore_assignments].where(id: stale[:id]).first
    expect(row[:user_id]).to eq(user_b[:id])
    expect(row[:pinned]).to be false
  end

  it "leaves pinned rows, past days, and today's started chores alone" do
    allow(Timezones).to receive_messages(today: Date.new(2026, 3, 2), now: Time.new(2026, 3, 2, 16, 0, 0))
    create_rsvp(user_a, start_date: event_start, end_date: event_start)
    create_rsvp(user_b)
    untimed = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
    morning = TestFactories.chore(chore_roster: roster, name: "Groceries", people_per_day: 1, time: "10:00")

    pinned = TestFactories.chore_assignment(chore: untimed, user: user_a, date: Date.new(2026, 3, 3), pinned: true)
    past = TestFactories.chore_assignment(chore: untimed, user: user_a, date: Date.new(2026, 3, 1), pinned: false)
    started = TestFactories.chore_assignment(chore: morning, user: user_a, date: Date.new(2026, 3, 2), pinned: false)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_b))
    expect(result.success?).to be true

    [pinned, past, started].each do |a|
      expect(DB[:chore_assignments].where(id: a[:id]).first[:user_id]).to eq(user_a[:id])
    end
  end

  it "spreads several stale slots across attendees by load" do
    # Alice holds both remaining days but left; Bob and Charlie are around.
    create_rsvp(user_a, start_date: event_start, end_date: event_start)
    create_rsvp(user_b)
    create_rsvp(user_c)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
    TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 3), pinned: false)
    TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 4), pinned: false)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_b))
    expect(result.success?).to be true

    holders = DB[:chore_assignments].where(chore_id: chore[:id]).select_map(:user_id)
    expect(holders).to contain_exactly(user_b[:id], user_c[:id])
  end

  it "leaves a stale row in place when nobody is attending that day" do
    create_rsvp(user_a, start_date: event_start, end_date: event_start)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
    orphan = TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 3), pinned: false)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))

    expect(result.success?).to be true
    expect(DB[:chore_assignments].where(id: orphan[:id]).first[:user_id]).to eq(user_a[:id])
  end

  it "broadcasts an update per reassigned row and succeeds as a no-op when nothing is stale" do
    create_rsvp(user_a, start_date: event_start, end_date: event_start)
    create_rsvp(user_b)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
    stale = TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 3), pinned: false)

    allow(Broadcaster).to receive(:object_changed)

    described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_b))
    expect(Broadcaster).to have_received(:object_changed)
      .with("chore_assignment", satisfy { |id| id.to_s == stale[:id] }).once

    # Second run: the roster is healthy, nothing moves, nothing broadcasts.
    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_b))
    expect(result.success?).to be true
    expect(result.value![:objects]).to eq([])
    expect(Broadcaster).to have_received(:object_changed).once
  end
end
