# frozen_string_literal: true

require "spec_helper"

RSpec.describe Attendances::Backfill do
  let(:workspace) { TestFactories.workspace }
  let(:alice) { TestFactories.user(name: "Alice") }
  let(:event) { TestFactories.event(workspace: workspace, user: alice) }

  before do
    TestFactories.workspace_membership(workspace: workspace, user: alice)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 3)
  end

  def member_attendance(user)
    Attendance.find_by_event_and_user(event[:id], user[:id])
  end

  describe "member rows" do
    it "mirrors attending, declined, day-set, and legacy-range rsvps" do
      whole = alice
      TestFactories.rsvp(event: event, user: whole, attending: true)

      declined = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: declined)
      TestFactories.rsvp(event: event, user: declined, attending: false)

      day_set = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: day_set)
      TestFactories.rsvp(
        event: event, user: day_set, attending: true,
        attendance: [Date.today.iso8601, { "date" => (Date.today + 2).iso8601, "plusOnes" => 1 }]
      )

      ranged = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: ranged)
      TestFactories.rsvp(event: event, user: ranged, attending: true, start_date: Date.today + 1, end_date: Date.today + 2)

      described_class.call

      expect(member_attendance(whole).status).to eq("going")
      expect(member_attendance(whole).days).to be_nil
      expect(member_attendance(declined).status).to eq("declined")
      expect(member_attendance(day_set).days).to eq([Date.today, Date.today + 2])
      expect(member_attendance(ranged).days).to eq([Date.today + 1, Date.today + 2])
    end

    it "normalizes a legacy range spanning the whole event to NULL days" do
      TestFactories.rsvp(event: event, user: alice, attending: true, start_date: Date.today, end_date: Date.today + 3)

      described_class.call

      expect(member_attendance(alice).status).to eq("going")
      expect(member_attendance(alice).days).to be_nil
    end
  end

  describe "plus-ones synthesis" do
    it "synthesizes placeholder guests: guest k attends the days where the count is at least k" do
      TestFactories.rsvp(
        event: event, user: alice, attending: true,
        attendance: [
          { "date" => Date.today.iso8601, "plusOnes" => 2 },
          { "date" => (Date.today + 1).iso8601, "plusOnes" => 1 }
        ]
      )

      described_class.call

      guests = Guest.for_workspace(workspace[:id])
      expect(guests.map(&:name)).to eq(["Guest 1 (Alice)", "Guest 2 (Alice)"])
      expect(guests.map(&:placeholder)).to all(be true)

      first, second = guests.map { |g| Attendance.find_by_event_and_guest(event[:id], g.id.to_s) }
      expect(first.status).to eq("going")
      expect(first.days).to eq([Date.today, Date.today + 1])
      expect(first.host_user_id.to_s).to eq(alice[:id])
      expect(second.days).to eq([Date.today])
    end

    it "normalizes a guest attending every event day to NULL days" do
      full_days = (Date.today..(Date.today + 3)).map { |d| { "date" => d.iso8601, "plusOnes" => 1 } }
      TestFactories.rsvp(event: event, user: alice, attending: true, attendance: full_days)

      described_class.call

      guest = Guest.for_workspace(workspace[:id]).first
      expect(Attendance.find_by_event_and_guest(event[:id], guest.id.to_s).days).to be_nil
    end

    it "is idempotent: re-running creates no duplicates and keeps ids stable" do
      TestFactories.rsvp(
        event: event, user: alice, attending: true,
        attendance: [{ "date" => Date.today.iso8601, "plusOnes" => 1 }]
      )

      described_class.call
      first_guest_ids = DB[:guests].select_map(:id).sort
      first_attendance_ids = DB[:attendances].select_map(:id).sort

      described_class.call

      expect(DB[:guests].select_map(:id).sort).to eq(first_guest_ids)
      expect(DB[:attendances].select_map(:id).sort).to eq(first_attendance_ids)
    end

    it "declines guests the counts no longer support on re-run, and revives them when counts grow" do
      rsvp_row = TestFactories.rsvp(
        event: event, user: alice, attending: true,
        attendance: [{ "date" => Date.today.iso8601, "plusOnes" => 2 }]
      )
      described_class.call
      expect(DB[:attendances].where(status: "going").exclude(guest_id: nil).count).to eq(2)

      DB[:rsvps].where(id: rsvp_row[:id]).update(
        attendance: Sequel.pg_jsonb([{ "date" => Date.today.iso8601, "plusOnes" => 1 }])
      )
      described_class.call

      going, declined = DB[:attendances].exclude(guest_id: nil).all.partition { |a| a[:status] == "going" }
      expect(going.length).to eq(1)
      expect(declined.length).to eq(1)
      expect(DB[:guests].count).to eq(2)

      DB[:rsvps].where(id: rsvp_row[:id]).update(
        attendance: Sequel.pg_jsonb([{ "date" => Date.today.iso8601, "plusOnes" => 2 }])
      )
      described_class.call

      expect(DB[:attendances].where(status: "going").exclude(guest_id: nil).count).to eq(2)
      expect(DB[:guests].count).to eq(2)
    end

    it "declines a host's placeholder guests when the host has declined" do
      rsvp_row = TestFactories.rsvp(
        event: event, user: alice, attending: true,
        attendance: [{ "date" => Date.today.iso8601, "plusOnes" => 1 }]
      )
      described_class.call

      DB[:rsvps].where(id: rsvp_row[:id]).update(attending: false, attendance: nil)
      described_class.call

      guest_rows = DB[:attendances].exclude(guest_id: nil).all
      expect(guest_rows.map { |a| a[:status] }).to all(eq("declined"))
    end

    it "declines placeholder guests whose host's rsvp was deleted since the last run" do
      rsvp_row = TestFactories.rsvp(
        event: event, user: alice, attending: true,
        attendance: [{ "date" => Date.today.iso8601, "plusOnes" => 1 }]
      )
      described_class.call

      DB[:rsvps].where(id: rsvp_row[:id]).delete
      described_class.call

      guest_rows = DB[:attendances].exclude(guest_id: nil).all
      expect(guest_rows.map { |a| a[:status] }).to all(eq("declined"))
    end

    it "leaves renamed (non-placeholder) guests and their attendances alone" do
      TestFactories.rsvp(
        event: event, user: alice, attending: true,
        attendance: [{ "date" => Date.today.iso8601, "plusOnes" => 1 }]
      )
      described_class.call
      guest = Guest.for_workspace(workspace[:id]).first
      membership = WorkspaceMembership.find_by_workspace_and_user(workspace[:id], alice[:id])
      Guests::Rename.call(workspace_id: workspace[:id], membership: membership, guest_id: guest.id.to_s, name: "Emma")
      DB[:attendances].where(guest_id: guest.id.to_s).update(days: Sequel.pg_jsonb([(Date.today + 1).iso8601]))

      described_class.call

      expect(DB[:guests].where(id: guest.id.to_s).get(:name)).to eq("Emma")
      expect(Attendance.find_by_event_and_guest(event[:id], guest.id.to_s).days).to eq([Date.today + 1])
    end

    it "keeps hosts' guests separate across events and hosts" do
      bob = TestFactories.user(name: "Bob")
      TestFactories.workspace_membership(workspace: workspace, user: bob)
      other_event = TestFactories.event(workspace: workspace, user: alice)
      DB[:events].where(id: other_event[:id]).update(start_date: Date.today, end_date: Date.today + 3)

      TestFactories.rsvp(event: event, user: alice, attending: true,
                         attendance: [{ "date" => Date.today.iso8601, "plusOnes" => 1 }]
      )
      TestFactories.rsvp(event: event, user: bob, attending: true,
                         attendance: [{ "date" => Date.today.iso8601, "plusOnes" => 1 }]
      )
      TestFactories.rsvp(event: other_event, user: alice, attending: true,
                         attendance: [{ "date" => Date.today.iso8601, "plusOnes" => 1 }]
      )

      described_class.call

      names = Guest.for_workspace(workspace[:id]).map(&:name)
      expect(names.sort).to eq(["Guest 1 (Alice)", "Guest 1 (Alice)", "Guest 1 (Bob)"])
      expect(DB[:attendances].exclude(guest_id: nil).count).to eq(3)
    end
  end
end
