# frozen_string_literal: true

require "spec_helper"

RSpec.describe Attendances::Upsert do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  def set_event_dates(days = 7)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + days)
  end

  def upsert(**kwargs)
    defaults = {
      event_id: event[:id],
      membership: @membership ||= membership_for(user),
      attendance_id: SecureRandom.uuid,
      status: "going"
    }
    described_class.call(**defaults.merge(kwargs))
  end

  describe "parameter validation" do
    it "requires a known status" do
      set_event_dates

      expect(upsert(user_id: user[:id], status: nil).failure.message).to eq("status is required")
      expect(upsert(user_id: user[:id], status: "maybe").failure.message).to eq("status must be one of pending, going, declined")
    end

    it "requires exactly one subject" do
      set_event_dates
      guest_row = TestFactories.guest(workspace: workspace)

      neither = upsert
      expect(neither.failure.message).to eq("user_id or guest is required")

      both = upsert(user_id: user[:id], guest_id: guest_row[:id])
      expect(both.failure.message).to eq("Attendance subject must be either a member or a guest, not both")
    end

    it "returns failure when the event is missing or has no dates" do
      not_found = upsert(event_id: "00000000-0000-0000-0000-000000000000", user_id: user[:id])
      expect(not_found.failure.message).to eq("Event not found")

      no_dates = upsert(user_id: user[:id])
      expect(no_dates.failure.message).to eq("Event does not have dates set")
    end

    it "returns failure when the member subject is not a workspace member" do
      set_event_dates
      stranger = TestFactories.user

      result = upsert(user_id: stranger[:id])
      expect(result.failure.message).to eq("User is not a member of this workspace")
    end
  end

  describe "member rows" do
    it "creates a going whole-event attendance under the client id" do
      set_event_dates
      client_id = SecureRandom.uuid

      result = upsert(user_id: user[:id], attendance_id: client_id)

      expect(result.value![:created]).to be true
      expect(result.value![:attendance_id].to_s).to eq(client_id)
      row = DB[:attendances].where(id: client_id).first
      expect(row[:status]).to eq("going")
      expect(row[:days]).to be_nil
      expect(row[:user_id]).to eq(user[:id])
      expect(row[:guest_id]).to be_nil
      expect(row[:host_user_id]).to be_nil
    end

    it "generates a server-side id when the client did not provide one" do
      set_event_dates

      result = upsert(user_id: user[:id], attendance_id: nil)

      expect(result.value![:created]).to be true
      expect(DB[:attendances].count).to eq(1)
    end

    it "stores a sorted, deduplicated day set within the event range" do
      set_event_dates
      days = [Date.today + 3, Date.today + 1, Date.today + 1].map(&:iso8601)

      result = upsert(user_id: user[:id], days: days)

      attendance = Attendance.find(result.value![:attendance_id])
      expect(attendance.days).to eq([Date.today + 1, Date.today + 3])
    end

    it "rejects malformed and out-of-range day sets" do
      set_event_dates

      invalid = upsert(user_id: user[:id], days: ["not-a-date"])
      expect(invalid.failure.message).to eq("Invalid date format")

      outside = upsert(user_id: user[:id], days: [(Date.today + 9).iso8601])
      expect(outside.failure.message).to eq("Days must fall within the event date range")

      not_array = upsert(user_id: user[:id], days: "2026-01-01")
      expect(not_array.failure.message).to eq("days must be a list of dates")
    end

    it "normalizes a full-coverage or empty day set to whole-event NULL" do
      set_event_dates(2)
      all_days = (Date.today..(Date.today + 2)).map(&:iso8601)

      full = upsert(user_id: user[:id], days: all_days)
      expect(DB[:attendances].where(id: full.value![:attendance_id].to_s).get(:days)).to be_nil

      empty = upsert(user_id: TestFactories.user.tap { |u| membership_for(u) }[:id], days: [])
      expect(DB[:attendances].where(id: empty.value![:attendance_id].to_s).get(:days)).to be_nil
    end

    it "keeps days NULL on pending and declined rows even when provided" do
      set_event_dates

      result = upsert(user_id: user[:id], status: "declined", days: [(Date.today + 1).iso8601])

      row = DB[:attendances].where(id: result.value![:attendance_id].to_s).first
      expect(row[:status]).to eq("declined")
      expect(row[:days]).to be_nil
    end

    it "updates the existing row and keeps its id and original filer on conflict" do
      set_event_dates
      other = TestFactories.user
      other_membership = membership_for(other)
      first = upsert(user_id: user[:id])
      existing_id = first.value![:attendance_id].to_s

      second = upsert(user_id: user[:id], membership: other_membership, status: "declined")

      expect(second.value![:created]).to be false
      expect(second.value![:attendance_id].to_s).to eq(existing_id)
      row = DB[:attendances].where(id: existing_id).first
      expect(row[:status]).to eq("declined")
      expect(row[:created_by_user_id]).to eq(user[:id])
      expect(DB[:attendances].count).to eq(1)
    end

    it "blocks declining while the subject has expenses on the event" do
      set_event_dates
      upsert(user_id: user[:id])
      now = Time.now
      DB[:expenses].insert(
        id: SecureRandom.uuid, event_id: event[:id], user_id: user[:id], amount: 50,
        description: "Dinner", start_date: Date.today, end_date: Date.today + 1,
        created_at: now, updated_at: now
      )

      result = upsert(user_id: user[:id], status: "declined")

      expect(result.failure.message).to eq("You cannot decline while you have expenses on this event")
      expect(result.failure.http_status).to eq(403)
    end

    it "blocks declining while the subject hosts going guests, but not pending ones" do
      set_event_dates
      upsert(user_id: user[:id])
      guest_row = TestFactories.guest(workspace: workspace)
      TestFactories.attendance(event: event, guest: guest_row, host: user, status: "going")

      blocked = upsert(user_id: user[:id], status: "declined")
      expect(blocked.failure.message).to eq("You cannot decline while you have guests going on this event")
      expect(blocked.failure.http_status).to eq(403)

      DB[:attendances].where(guest_id: guest_row[:id]).update(status: "pending", days: nil)
      allowed = upsert(user_id: user[:id], status: "declined")
      expect(allowed.success?).to be true
    end
  end

  describe "guest rows" do
    it "creates an attendance for an existing guest with the actor as default host" do
      set_event_dates
      guest_row = TestFactories.guest(workspace: workspace)

      result = upsert(guest_id: guest_row[:id])

      row = DB[:attendances].where(id: result.value![:attendance_id].to_s).first
      expect(row[:guest_id]).to eq(guest_row[:id])
      expect(row[:user_id]).to be_nil
      expect(row[:host_user_id]).to eq(user[:id])
    end

    it "creates guest and attendance together from an inline payload, idempotently" do
      set_event_dates
      guest_id = SecureRandom.uuid
      attendance_id = SecureRandom.uuid

      result = upsert(guest: { "id" => guest_id, "name" => "Emma" }, attendance_id: attendance_id)

      expect(result.value![:created]).to be true
      guest = DB[:guests].where(id: guest_id).first
      expect(guest[:name]).to eq("Emma")
      expect(guest[:workspace_id]).to eq(workspace[:id])
      expect(guest[:placeholder]).to be false
      expect(guest[:created_by_user_id]).to eq(user[:id])
      expect(DB[:attendances].where(id: attendance_id).get(:guest_id)).to eq(guest_id)

      replay = upsert(guest: { "id" => guest_id, "name" => "Emma" }, attendance_id: attendance_id)
      expect(replay.value![:created]).to be false
      expect(DB[:guests].count).to eq(1)
      expect(DB[:attendances].count).to eq(1)
    end

    it "does not overwrite an existing guest's name from an inline replay" do
      set_event_dates
      guest_row = TestFactories.guest(workspace: workspace, name: "Emma")

      upsert(guest: { "id" => guest_row[:id], "name" => "Someone Else" })

      expect(DB[:guests].where(id: guest_row[:id]).get(:name)).to eq("Emma")
    end

    it "validates the inline guest name" do
      set_event_dates

      blank = upsert(guest: { "id" => SecureRandom.uuid, "name" => "  " })
      expect(blank.failure.message).to eq("Name is required")

      long = upsert(guest: { "id" => SecureRandom.uuid, "name" => "a" * 256 })
      expect(long.failure.message).to eq("Name is too long (maximum 255 characters)")
    end

    it "rejects guests from another workspace and unknown guest ids" do
      set_event_dates
      foreign_guest = TestFactories.guest

      foreign = upsert(guest_id: foreign_guest[:id])
      expect(foreign.failure.message).to eq("Guest is not part of this workspace")

      unknown = upsert(guest_id: SecureRandom.uuid)
      expect(unknown.failure.message).to eq("Guest not found")
      expect(unknown.failure.http_status).to eq(404)
    end

    it "requires an explicit host to be a workspace member" do
      set_event_dates
      guest_row = TestFactories.guest(workspace: workspace)
      stranger = TestFactories.user

      result = upsert(guest_id: guest_row[:id], host_user_id: stranger[:id])

      expect(result.failure.message).to eq("Host is not a member of this workspace")
    end

    it "re-adds a removed guest by flipping the same row back to going" do
      set_event_dates
      guest_row = TestFactories.guest(workspace: workspace)
      first = upsert(guest_id: guest_row[:id])
      existing_id = first.value![:attendance_id].to_s

      upsert(guest_id: guest_row[:id], status: "declined")
      readded = upsert(guest_id: guest_row[:id], attendance_id: SecureRandom.uuid)

      expect(readded.value![:attendance_id].to_s).to eq(existing_id)
      expect(DB[:attendances].where(id: existing_id).get(:status)).to eq("going")
      expect(DB[:attendances].count).to eq(1)
    end

    it "keeps the existing host unless a new one is passed explicitly" do
      set_event_dates
      guest_row = TestFactories.guest(workspace: workspace)
      other = TestFactories.user
      other_membership = membership_for(other)
      upsert(guest_id: guest_row[:id]) # hosted by `user`

      upsert(guest_id: guest_row[:id], membership: other_membership, days: [(Date.today + 1).iso8601])
      expect(DB[:attendances].where(guest_id: guest_row[:id]).get(:host_user_id)).to eq(user[:id])

      upsert(guest_id: guest_row[:id], membership: other_membership, host_user_id: other[:id])
      expect(DB[:attendances].where(guest_id: guest_row[:id]).get(:host_user_id)).to eq(other[:id])
    end
  end
end
