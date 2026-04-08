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
