# frozen_string_literal: true

require "spec_helper"

RSpec.describe AttendanceSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:event_row) { TestFactories.event(workspace: workspace, user: user) }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:attendance_row) { TestFactories.attendance(event: event_row, user: user) }
      let(:pool_object) { described_class.serialize_batch([Attendance.find(attendance_row[:id])], pool: nil).first }

      it_behaves_like "a pool object with createdAt", "attendance"
    end

    it "serializes a member row with a day set" do
      row = TestFactories.attendance(event: event_row, user: user, status: "going", days: [Date.today + 1, Date.today], created_by: user)

      result = described_class.serialize_batch([Attendance.find(row[:id])], pool: nil).first

      expect(result[:eventId]).to eq(event_row[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:guestId]).to be_nil
      expect(result[:hostUserId]).to be_nil
      expect(result[:status]).to eq("going")
      expect(result[:days]).to eq([Date.today.iso8601, (Date.today + 1).iso8601])
      expect(result[:createdByUserId]).to eq(user[:id].to_s)
    end

    it "serializes a whole-event guest row" do
      guest = TestFactories.guest(workspace: workspace)
      row = TestFactories.attendance(event: event_row, guest: guest, host: user)

      result = described_class.serialize_batch([Attendance.find(row[:id])], pool: nil).first

      expect(result[:userId]).to be_nil
      expect(result[:guestId]).to eq(guest[:id].to_s)
      expect(result[:hostUserId]).to eq(user[:id].to_s)
      expect(result[:days]).to be_nil
    end
  end

  describe ".policy_context_batch" do
    it "flags member rows whose subject has expenses or hosts going guests" do
      blocked_row = TestFactories.attendance(event: event_row, user: user)
      now = Time.now
      DB[:expenses].insert(
        id: SecureRandom.uuid, event_id: event_row[:id], user_id: user[:id], amount: 10,
        description: "Dinner", start_date: Date.today, end_date: Date.today,
        created_at: now, updated_at: now
      )
      host = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace, user: host)
      hosting_row = TestFactories.attendance(event: event_row, user: host)
      guest = TestFactories.guest(workspace: workspace)
      TestFactories.attendance(event: event_row, guest: guest, host: host, status: "going")

      contexts = described_class.policy_context_batch(
        [blocked_row, hosting_row].map { |r| Attendance.find(r[:id]) }
      )

      expect(contexts[blocked_row[:id]]).to eq({ has_expenses: true, has_going_guests: false })
      expect(contexts[hosting_row[:id]]).to eq({ has_expenses: false, has_going_guests: true })
    end

    it "does not flag hosts whose guests are merely pending" do
      hosting_row = TestFactories.attendance(event: event_row, user: user)
      guest = TestFactories.guest(workspace: workspace)
      TestFactories.attendance(event: event_row, guest: guest, host: user, status: "pending")

      contexts = described_class.policy_context_batch([Attendance.find(hosting_row[:id])])

      expect(contexts[hosting_row[:id]]).to eq({ has_expenses: false, has_going_guests: false })
    end
  end
end
