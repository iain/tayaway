# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::Autofill do
  let(:user_a) { TestFactories.user(name: "Alice") }
  let(:user_b) { TestFactories.user(name: "Bob") }
  let(:user_c) { TestFactories.user(name: "Charlie") }
  let(:workspace) { TestFactories.workspace }
  let(:event_start) { Date.new(2026, 3, 1) }
  let(:event_end) { Date.new(2026, 3, 3) }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user_a)
    DB[:events].where(id: e[:id]).update(start_date: event_start, end_date: event_end)
    DB[:events].where(id: e[:id]).first
  end
  let(:roster) { TestFactories.chore_roster(event: event, user: user_a) }

  # Anchor "today" before the event so the long-standing specs keep describing
  # a roster filled ahead of time; the mid-event block below moves it.
  before { allow(Timezones).to receive(:today).and_return(Date.new(2026, 2, 1)) }

  def membership_for(usr)
    existing = DB[:workspace_memberships].where(workspace_id: workspace[:id], user_id: usr[:id]).first
    row = existing || TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  define_method(:create_rsvp) do |user, start_date: nil, end_date: nil|
    TestFactories.rsvp(event: event, user: user, attending: true, start_date: start_date, end_date: end_date)
  end

  define_method(:non_pinned_assignments) do
    DB[:chore_assignments]
      .join(:chores, id: :chore_id)
      .where(Sequel[:chores][:chore_roster_id] => roster[:id])
      .where(Sequel[:chore_assignments][:pinned] => false)
      .select_all(:chore_assignments)
      .all
  end

  define_method(:all_assignments) do
    DB[:chore_assignments]
      .join(:chores, id: :chore_id)
      .where(Sequel[:chores][:chore_roster_id] => roster[:id])
      .select_all(:chore_assignments)
      .all
  end

  it "fills slots based on RSVP availability" do
    create_rsvp(user_a)
    create_rsvp(user_b)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))

    expect(result.success?).to be true

    # 3 days, 1 person/day = 3 assignments
    assignments = non_pinned_assignments.select { |a| a[:chore_id] == chore[:id] }
    expect(assignments.length).to eq(3)

    # Each day should have exactly one person
    by_date = assignments.group_by { |a| a[:date] }
    by_date.each_value do |day_assignments|
      expect(day_assignments.length).to eq(1)
    end
  end

  it "schedules a reminder for each autofilled assignment of a timed chore" do
    allow(Jobs::Queue).to receive(:enqueue)
    future = TestFactories.event(workspace: workspace, user: user_a)
    DB[:events].where(id: future[:id]).update(start_date: Date.new(2099, 5, 1), end_date: Date.new(2099, 5, 2))
    future = DB[:events].where(id: future[:id]).first
    future_roster = TestFactories.chore_roster(event: future, user: user_a)
    TestFactories.rsvp(event: future, user: user_a, attending: true, start_date: nil, end_date: nil)
    TestFactories.chore(chore_roster: future_roster, name: "Cooking", people_per_day: 1, time: "08:00")

    result = described_class.call(roster_id: future_roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
    expect(result.success?).to be true

    created = DB[:chore_assignments].join(:chores, id: :chore_id)
                                    .where(Sequel[:chores][:chore_roster_id] => future_roster[:id]).count
    expect(created).to eq(2)
    expect(Jobs::Queue).to have_received(:enqueue)
      .with(hash_including(job_class: "ChoreRosters::SendReminder::Job")).twice
  end

  it "preserves pinned assignments" do
    create_rsvp(user_a)
    create_rsvp(user_b)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)

    # Pin Alice to day 1
    TestFactories.chore_assignment(
      chore: chore,
      user: user_a,
      date: event_start,
      pinned: true,
      note: "Pizza night"
    )

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
    expect(result.success?).to be true

    # Pinned assignment should still exist
    pinned = all_assignments.select { |a| a[:pinned] }
    expect(pinned.length).to eq(1)
    expect(pinned.first[:user_id]).to eq(user_a[:id])
    expect(pinned.first[:date]).to eq(event_start)
    expect(pinned.first[:note]).to eq("Pizza night")
  end

  it "respects one-chore-per-day rule when possible" do
    create_rsvp(user_a)
    create_rsvp(user_b)
    TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
    TestFactories.chore(chore_roster: roster, name: "Washing", people_per_day: 1)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
    expect(result.success?).to be true

    # With 2 people and 2 chores, no one should have 2 chores on the same day
    assignments = non_pinned_assignments
    by_user_date = assignments.group_by { |a| [a[:user_id], a[:date]] }
    by_user_date.each_value do |day_assignments|
      expect(day_assignments.length).to eq(1)
    end
  end

  it "relaxes one-per-day when not enough people" do
    create_rsvp(user_a)
    # Only one person for 2 chores
    TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
    TestFactories.chore(chore_roster: roster, name: "Washing", people_per_day: 1)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
    expect(result.success?).to be true

    # Should fill all 6 slots (3 days * 2 chores) with Alice
    assignments = non_pinned_assignments
    expect(assignments.length).to eq(6)
    expect(assignments.all? { |a| a[:user_id] == user_a[:id] }).to be true
  end

  it "distributes fairly based on available days" do
    # Alice available all 3 days, Bob only day 1
    create_rsvp(user_a)
    create_rsvp(user_b, start_date: event_start, end_date: event_start)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
    expect(result.success?).to be true

    assignments = non_pinned_assignments.select { |a| a[:chore_id] == chore[:id] }

    # Bob should get day 1 (ratio 0/1=0 vs Alice 0/3=0 — tie, but Bob has fewer days available)
    # Alice should get days 2 and 3
    bob_assignments = assignments.select { |a| a[:user_id] == user_b[:id] }
    alice_assignments = assignments.select { |a| a[:user_id] == user_a[:id] }
    expect(bob_assignments.length).to be >= 1
    expect(alice_assignments.length).to be >= 1
    expect(assignments.length).to eq(3)
  end

  it "deletes non-pinned assignments before re-filling" do
    create_rsvp(user_a)
    create_rsvp(user_b)
    TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)

    # First autofill
    described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
    first_ids = non_pinned_assignments.map { |a| a[:id] }
    expect(first_ids.length).to eq(3)

    # Second autofill — old non-pinned should be deleted
    described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
    second_ids = non_pinned_assignments.map { |a| a[:id] }
    expect(second_ids.length).to eq(3)

    # IDs should be different (old ones deleted, new ones created)
    expect((first_ids & second_ids).length).to eq(0)
  end

  it "broadcasts a deletion per removed assignment so connected clients drop the stale rows" do
    create_rsvp(user_a)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
    stale = TestFactories.chore_assignment(chore: chore, user: user_a, date: event_start, pinned: false)

    allow(Broadcaster).to receive(:object_deleted)
    allow(Broadcaster).to receive(:object_changed)

    described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))

    expect(Broadcaster).to have_received(:object_deleted)
      .with("chore_assignment", stale[:id], topics: [Topic.workspace(workspace[:id])])
  end

  it "handles partial RSVP date ranges" do
    # Alice only available days 1–2, Charlie only day 3
    create_rsvp(user_a, start_date: event_start, end_date: event_start + 1)
    create_rsvp(user_c, start_date: event_end, end_date: event_end)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
    expect(result.success?).to be true

    assignments = non_pinned_assignments.select { |a| a[:chore_id] == chore[:id] }
    expect(assignments.length).to eq(3)

    day3 = assignments.find { |a| a[:date] == event_end }
    expect(day3[:user_id]).to eq(user_c[:id])
  end

  it "succeeds with no RSVPs (no assignments created)" do
    TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))

    expect(result.success?).to be true
    expect(non_pinned_assignments.length).to eq(0)
  end

  it "succeeds with no chores (nothing to fill)" do
    create_rsvp(user_a)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))

    expect(result.success?).to be true
    expect(all_assignments.length).to eq(0)
  end

  it "distributes chore variety across people" do
    # 6 days so patterns emerge
    DB[:events].where(id: event[:id]).update(end_date: event_start + 5)

    create_rsvp(user_a)
    create_rsvp(user_b)
    TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
    TestFactories.chore(chore_roster: roster, name: "Cleaning", people_per_day: 1)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
    expect(result.success?).to be true

    assignments = non_pinned_assignments
    # Each person should do each chore at least twice (out of 6 days)
    %w[Cooking Cleaning].each do |chore_name|
      chore_id = DB[:chores].where(name: chore_name, chore_roster_id: roster[:id]).first[:id]
      [user_a, user_b].each do |user|
        count = assignments.count { |a| a[:chore_id] == chore_id && a[:user_id] == user[:id] }
        expect(count).to be >= 2, "#{user[:name]} should do #{chore_name} at least twice, got #{count}"
      end
    end
  end

  it "does not pile extra chores onto someone already pinned to their fair share" do
    # 6-day event, three people all available every day.
    DB[:events].where(id: event[:id]).update(end_date: event_start + 5)
    create_rsvp(user_a) # the "chef"
    create_rsvp(user_b)
    create_rsvp(user_c)

    koken = TestFactories.chore(chore_roster: roster, name: "Koken", people_per_day: 1)
    TestFactories.chore(chore_roster: roster, name: "Schoonmaak", people_per_day: 1)

    # Chef is pinned to Koken on the first four days (their standing role). That
    # leaves 8 open slots (2 Koken + 6 Schoonmaak) and, with 12 slots over 3
    # people, a fair share of 4 each — the chef is already there on pins alone.
    (0..3).each do |offset|
      TestFactories.chore_assignment(chore: koken, user: user_a, date: event_start + offset, pinned: true)
    end

    described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))

    # Autofill should hand the already-loaded chef no additional work...
    chef_extra = non_pinned_assignments.count { |a| a[:user_id] == user_a[:id] }
    expect(chef_extra).to eq(0)

    # ...and the remaining work should spread evenly across the other two.
    totals = all_assignments.group_by { |a| a[:user_id] }.transform_values(&:length)
    expect(totals.values.max - totals.values.min).to be <= 1
  end

  describe "mid-event" do
    let(:event_end) { Date.new(2026, 3, 4) }

    before { allow(Timezones).to receive(:today).and_return(Date.new(2026, 3, 3)) }

    it "leaves days before today untouched and refills only from today onward" do
      create_rsvp(user_a)
      create_rsvp(user_b)
      chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)

      past1 = TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 1), pinned: false)
      past2 = TestFactories.chore_assignment(chore: chore, user: user_b, date: Date.new(2026, 3, 2), pinned: false)
      stale_future = TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 3), pinned: false)

      result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
      expect(result.success?).to be true

      # The record of days already gone keeps its exact rows.
      expect(DB[:chore_assignments].where(id: [past1[:id], past2[:id]]).count).to eq(2)
      # Today's old row was cleared and the remaining days are all filled.
      expect(DB[:chore_assignments].where(id: stale_future[:id]).count).to eq(0)
      expect(all_assignments.map { |a| a[:date] }.sort)
        .to eq([Date.new(2026, 3, 1), Date.new(2026, 3, 2), Date.new(2026, 3, 3), Date.new(2026, 3, 4)])
    end

    it "leaves a timed chore already started today as the record of who did it" do
      allow(Timezones).to receive(:now).and_return(Time.new(2026, 3, 3, 16, 0, 0))
      create_rsvp(user_a)
      create_rsvp(user_b)
      morning = TestFactories.chore(chore_roster: roster, name: "Groceries", people_per_day: 1, time: "10:00")
      done = TestFactories.chore_assignment(chore: morning, user: user_a, date: Date.new(2026, 3, 3), pinned: false)

      result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
      expect(result.success?).to be true

      # The 10:00 run was already done by 16:00 — its exact row stays...
      expect(DB[:chore_assignments].where(id: done[:id]).count).to eq(1)
      # ...and only tomorrow gets a fresh slot for this chore.
      rows = all_assignments.select { |a| a[:chore_id] == morning[:id] }
      expect(rows.map { |a| a[:date] }).to contain_exactly(Date.new(2026, 3, 3), Date.new(2026, 3, 4))
    end

    it "still refills a timed chore that has not started yet today" do
      allow(Timezones).to receive(:now).and_return(Time.new(2026, 3, 3, 16, 0, 0))
      create_rsvp(user_a)
      create_rsvp(user_b)
      dinner = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1, time: "17:00")
      stale = TestFactories.chore_assignment(chore: dinner, user: user_a, date: Date.new(2026, 3, 3), pinned: false)

      result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
      expect(result.success?).to be true

      expect(DB[:chore_assignments].where(id: stale[:id]).count).to eq(0)
      rows = all_assignments.select { |a| a[:chore_id] == dinner[:id] }
      expect(rows.map { |a| a[:date] }).to contain_exactly(Date.new(2026, 3, 3), Date.new(2026, 3, 4))
    end

    it "counts past work when balancing the remaining days" do
      # Alice covered the two days already gone; both are around all four days.
      # The two remaining days should both fall to Bob (Alice 2/4 vs Bob 0/4).
      create_rsvp(user_a)
      create_rsvp(user_b)
      chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
      TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 1), pinned: false)
      TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 2), pinned: false)

      result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))
      expect(result.success?).to be true

      remaining = all_assignments.select { |a| a[:date] >= Date.new(2026, 3, 3) }
      expect(remaining.map { |a| a[:user_id] }).to eq([user_b[:id], user_b[:id]])
    end

    it "fails when the event is already over, leaving the roster untouched" do
      allow(Timezones).to receive(:today).and_return(Date.new(2026, 3, 10))
      create_rsvp(user_a)
      chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)
      done = TestFactories.chore_assignment(chore: chore, user: user_a, date: Date.new(2026, 3, 2), pinned: false)

      result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))

      expect(result.failure?).to be true
      expect(result.failure.message).to match(/event is over/i)
      expect(DB[:chore_assignments].where(id: done[:id]).count).to eq(1)
    end
  end

  it "keeps pinned-only state when all assignments are pinned" do
    create_rsvp(user_a)
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1)

    # Pin all 3 days
    (event_start..event_end).each do |date|
      TestFactories.chore_assignment(chore: chore, user: user_a, date: date, pinned: true)
    end

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user_a))

    expect(result.success?).to be true
    # All 3 pinned should remain, no non-pinned created (slots full)
    expect(all_assignments.length).to eq(3)
    expect(all_assignments.all? { |a| a[:pinned] }).to be true
  end
end
