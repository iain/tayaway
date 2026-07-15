# frozen_string_literal: true

require "spec_helper"

RSpec.describe Attendance do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:event_row) { TestFactories.event(workspace: workspace, user: user) }
  let(:event) { Event.find(event_row[:id]) }

  before do
    TestFactories.workspace_membership(workspace: workspace, user: user)
    DB[:events].where(id: event_row[:id]).update(start_date: Date.today, end_date: Date.today + 3)
  end

  def find_attendance(**kwargs)
    row = TestFactories.attendance(event: event_row, **kwargs)
    described_class.find(row[:id])
  end

  describe "days parsing" do
    it "parses the jsonb day set into sorted dates" do
      attendance = find_attendance(user: user, days: [Date.today + 2, Date.today])

      expect(attendance.days).to eq([Date.today, Date.today + 2])
    end

    it "returns nil days for a whole-event row" do
      attendance = find_attendance(user: user)

      expect(attendance.days).to be_nil
    end

    it "treats an empty day set as nil" do
      row = TestFactories.attendance(event: event_row, user: user)
      DB[:attendances].where(id: row[:id]).update(days: Sequel.pg_jsonb([]))

      expect(described_class.find(row[:id]).days).to be_nil
    end
  end

  describe "#effective_days" do
    it "returns the explicit day set when present" do
      attendance = find_attendance(user: user, days: [Date.today + 1])

      expect(attendance.effective_days(event)).to eq([Date.today + 1])
    end

    it "falls back to the whole event range when days is nil" do
      attendance = find_attendance(user: user)

      expect(attendance.effective_days(event)).to eq((Date.today..(Date.today + 3)).to_a)
    end
  end

  describe "#attendee" do
    it "resolves a member row to the user with the user as billing target" do
      attendance = find_attendance(user: user)
      attendee = attendance.attendee

      expect(attendee.guest?).to be false
      expect(attendee.display_name).to eq(user[:name])
      expect(attendee.user_id.to_s).to eq(user[:id])
      expect(attendee.billing_user_id.to_s).to eq(user[:id])
    end

    it "resolves a guest row to the guest with the host as billing target" do
      guest = TestFactories.guest(workspace: workspace, name: "Emma")
      attendance = find_attendance(guest: guest, host: user)
      attendee = attendance.attendee

      expect(attendee.guest?).to be true
      expect(attendee.display_name).to eq("Emma")
      expect(attendee.user_id).to be_nil
      expect(attendee.billing_user_id.to_s).to eq(user[:id])
    end
  end

  describe "status predicates" do
    it "knows going from pending and declined" do
      expect(find_attendance(user: user, status: "going").going?).to be true
      expect(find_attendance(user: TestFactories.user, status: "pending").going?).to be false
    end

    it "knows guest rows from member rows" do
      guest = TestFactories.guest(workspace: workspace)

      expect(find_attendance(user: user).guest?).to be false
      expect(find_attendance(guest: guest, host: user).guest?).to be true
    end
  end

  describe "finders" do
    it "finds by event and user, and by event and guest" do
      guest = TestFactories.guest(workspace: workspace)
      member_row = TestFactories.attendance(event: event_row, user: user)
      guest_row = TestFactories.attendance(event: event_row, guest: guest, host: user)

      expect(described_class.find_by_event_and_user(event_row[:id], user[:id]).id.to_s).to eq(member_row[:id])
      expect(described_class.find_by_event_and_guest(event_row[:id], guest[:id]).id.to_s).to eq(guest_row[:id])
    end

    it "returns all rows for an event and batch ids per event" do
      other_event = TestFactories.event(workspace: workspace, user: user)
      row = TestFactories.attendance(event: event_row, user: user)
      TestFactories.attendance(event: other_event, user: user)

      expect(described_class.for_event(event_row[:id]).map { |a| a.id.to_s }).to eq([row[:id]])
      ids = described_class.ids_for_event_ids([event_row[:id], other_event[:id]])
      expect(ids[event_row[:id]]).to eq([row[:id]])
      expect(ids.values.flatten.length).to eq(2)
    end

    it "returns rows changed since a timestamp scoped to the workspace" do
      row = TestFactories.attendance(event: event_row, user: user)

      changed = described_class.changed_since(workspace[:id], Time.now - 60)
      expect(changed.map { |a| a.id.to_s }).to include(row[:id])
      expect(described_class.changed_since(workspace[:id], Time.now + 60)).to be_empty
    end

    it "distinguishes gone from not found via deleted_items" do
      missing = described_class.find_result(SecureRandom.uuid)
      expect(missing.failure.http_status).to eq(404)

      tombstoned_id = SecureRandom.uuid
      DB[:deleted_items].insert(workspace_id: workspace[:id], object_type: "attendance", object_id: tombstoned_id)
      gone = described_class.find_result(tombstoned_id)
      expect(gone.failure.http_status).to eq(410)
    end
  end
end
