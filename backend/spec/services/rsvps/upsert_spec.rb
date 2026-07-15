# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rsvps::Upsert do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "returns failure when attending is nil" do
    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: nil, rsvp_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("attending is required")
  end

  it "generates a server-side rsvp_id when none is provided" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: true, rsvp_id: nil)

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:rsvp_id]).not_to be_nil
    expect(DB[:rsvps].count).to eq(1)
  end

  it "returns failure when event not found" do
    result = described_class.call(
      event_id: "00000000-0000-0000-0000-000000000000",
      membership: membership_for(user),
      user_id: user[:id],
      attending: true,
      rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Event not found")
  end

  it "returns failure when event has no dates set" do
    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Event does not have dates set")
  end

  it "creates an RSVP when event has dates" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: true, rsvp_id: client_id)

    expect(result.success?).to be true
    expect(result.value![:created]).to be true
    expect(result.value![:rsvp_id].to_s).to eq(client_id)
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be true
    expect(rsvp[:start_date]).to be_nil
    expect(rsvp[:end_date]).to be_nil
  end

  it "uses client-provided rsvp_id for new RSVP" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    result = described_class.call(event_id: event[:id], membership: membership_for(user), user_id: user[:id], attending: true, rsvp_id: client_id)

    expect(result.success?).to be true
    expect(DB[:rsvps].where(id: client_id).count).to eq(1)
  end

  it "creates an RSVP with partial dates" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      user_id: user[:id],
      attending: true,
      start_date: (Date.today + 1).iso8601,
      end_date: (Date.today + 3).iso8601,
      rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be true
    expect(rsvp[:start_date]).to eq(Date.today + 1)
    expect(rsvp[:end_date]).to eq(Date.today + 3)
  end

  it "returns failure when partial dates are outside event range" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      user_id: user[:id],
      attending: true,
      start_date: (Date.today - 1).iso8601,
      end_date: (Date.today + 3).iso8601,
      rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Partial dates must fall within the event date range")
  end

  it "clears partial dates when not attending" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id],
      membership: membership_for(user),
      user_id: user[:id],
      attending: false,
      start_date: (Date.today + 1).iso8601,
      end_date: (Date.today + 3).iso8601,
      rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be false
    expect(rsvp[:start_date]).to be_nil
    expect(rsvp[:end_date]).to be_nil
  end

  it "updates existing RSVP and returns created: false" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result1 = described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)
    expect(result1.value![:created]).to be true

    result2 = described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid)
    expect(result2.success?).to be true
    expect(result2.value![:created]).to be false

    rsvp = DB[:rsvps].where(id: result2.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be false
    expect(DB[:rsvps].count).to eq(1)
  end

  it "returns failure when declining with expenses on the event" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    # RSVP as attending first
    described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)

    # Create an expense on this event
    now = Time.now
    DB[:expenses].insert(
      id: SecureRandom.uuid,
      event_id: event[:id],
      user_id: user[:id],
      amount: 50,
      description: "Dinner",
      start_date: Date.today,
      end_date: Date.today + 1,
      created_at: now,
      updated_at: now
    )

    result = described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("You cannot decline while you have expenses on this event")
    expect(result.failure.http_status).to eq(403)
  end

  it "allows declining when user has no expenses on the event" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: SecureRandom.uuid)

    result = described_class.call(event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid)

    expect(result.success?).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:attending]).to be false
  end

  it "updates existing RSVP when called with the existing rsvp_id and changed values" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: client_id
    )
    result = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: client_id
    )

    expect(result.success?).to be true
    expect(result.value![:created]).to be false
    expect(result.value![:rsvp_id].to_s).to eq(client_id)
    rsvp = DB[:rsvps].where(id: client_id).first
    expect(rsvp[:attending]).to be false
    expect(DB[:rsvps].count).to eq(1)
  end

  it "returns existing RSVP on idempotent replay with same rsvp_id" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    client_id = SecureRandom.uuid

    result1 = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: client_id
    )
    result2 = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: true, rsvp_id: client_id
    )

    expect(result1.success?).to be true
    expect(result1.value![:created]).to be true
    expect(result2.success?).to be true
    expect(result2.value![:created]).to be false
    expect(DB[:rsvps].where(id: client_id).count).to eq(1)
  end

  it "lets a workspace member RSVP on behalf of another member" do
    other = TestFactories.user
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    actor_membership = membership_for(user)
    membership_for(other) # ensure subject is a workspace member

    result = described_class.call(
      event_id: event[:id], membership: actor_membership, user_id: other[:id], attending: true, rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = DB[:rsvps].where(id: result.value![:rsvp_id]).first
    expect(rsvp[:user_id]).to eq(other[:id])
  end

  it "returns failure when subject is not a workspace member" do
    stranger = TestFactories.user
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: stranger[:id], attending: true, rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("User is not a member of this workspace")
  end

  it "returns failure when user_id is missing" do
    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: nil, attending: true, rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("user_id is required")
  end

  it "returns existing RSVP when a row already exists for this event+user under a different id" do
    membership = membership_for(user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    existing_id = SecureRandom.uuid
    TestFactories.rsvp(id: existing_id, event: event, user: user, attending: true)

    # Client sends a new id but event+user already has an RSVP — ON CONFLICT updates
    # the existing row and returns its id.
    result = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: false, rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    expect(result.value![:rsvp_id].to_s).to eq(existing_id)
    expect(result.value![:created]).to be false
    expect(DB[:rsvps].where(id: existing_id).get(:attending)).to be false
    expect(DB[:rsvps].count).to eq(1)
  end

  it "creates an RSVP with a come-and-go day set and keeps the contiguous hull" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    days = [Date.today + 1, Date.today + 3, Date.today + 4]

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: user[:id],
      attending: true, attendance: days.map(&:iso8601), rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = Rsvp.find(result.value![:rsvp_id])
    expect(rsvp.attendance.map { |day| day[:date] }).to eq(days)
    expect(rsvp.attendance.map { |day| day[:plus_ones] }).to all(eq(0))
    expect(rsvp.start_date).to eq(Date.today + 1)
    expect(rsvp.end_date).to eq(Date.today + 4)
  end

  it "stores per-day plus-ones from an object day set" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    attendance = [
      { "date" => (Date.today + 1).iso8601, "plusOnes" => 2 },
      { "date" => (Date.today + 2).iso8601, "plusOnes" => 0 }
    ]

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: user[:id],
      attending: true, attendance: attendance, rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = Rsvp.find(result.value![:rsvp_id])
    expect(rsvp.attendance).to eq(
      [{ date: Date.today + 1, plus_ones: 2 }, { date: Date.today + 2, plus_ones: 0 }]
    )
    # Hull still spans the day set for legacy readers.
    expect(rsvp.start_date).to eq(Date.today + 1)
    expect(rsvp.end_date).to eq(Date.today + 2)
  end

  it "keeps a full-event day set that carries guests rather than collapsing to whole-event" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 2)
    attendance = [Date.today, Date.today + 1, Date.today + 2].map.with_index do |date, i|
      { "date" => date.iso8601, "plusOnes" => i.zero? ? 1 : 0 }
    end

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: user[:id],
      attending: true, attendance: attendance, rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = Rsvp.find(result.value![:rsvp_id])
    # All days are selected, but the guest means it can't reduce to nil.
    expect(rsvp.attendance).not_to be_nil
    expect(rsvp.attendance.sum { |day| day[:plus_ones] }).to eq(1)
  end

  it "rejects a plus-one count outside the allowed range" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
    membership = membership_for(user)

    over_cap = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: true,
      attendance: [{ "date" => (Date.today + 1).iso8601, "plusOnes" => ValidationLimits::PLUS_ONES_PER_DAY_MAX + 1 }],
      rsvp_id: SecureRandom.uuid
    )
    expect(over_cap.failure?).to be true
    expect(over_cap.failure.message).to match(/guest/i)

    negative = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: true,
      attendance: [{ "date" => (Date.today + 1).iso8601, "plusOnes" => -1 }],
      rsvp_id: SecureRandom.uuid
    )
    expect(negative.failure?).to be true
    expect(negative.failure.message).to match(/guest/i)

    # A non-integer guest count is a guest problem, not a date-format one.
    non_integer = described_class.call(
      event_id: event[:id], membership: membership, user_id: user[:id], attending: true,
      attendance: [{ "date" => (Date.today + 1).iso8601, "plusOnes" => "abc" }],
      rsvp_id: SecureRandom.uuid
    )
    expect(non_integer.failure?).to be true
    expect(non_integer.failure.message).to match(/guest/i)
  end

  it "rejects a come-and-go day set with dates outside the event range" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: user[:id],
      attending: true, attendance: [(Date.today + 1).iso8601, (Date.today + 9).iso8601], rsvp_id: SecureRandom.uuid
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Attendance dates must fall within the event date range")
  end

  it "normalizes a full-event day set to a whole-event RSVP (nil attendance)" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 2)
    all_days = [Date.today, Date.today + 1, Date.today + 2].map(&:iso8601)

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: user[:id],
      attending: true, attendance: all_days, rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = Rsvp.find(result.value![:rsvp_id])
    expect(rsvp.attendance).to be_nil
    expect(rsvp.start_date).to be_nil
    expect(rsvp.end_date).to be_nil
  end

  it "clears the day set when not attending" do
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)

    result = described_class.call(
      event_id: event[:id], membership: membership_for(user), user_id: user[:id],
      attending: false, attendance: [(Date.today + 1).iso8601], rsvp_id: SecureRandom.uuid
    )

    expect(result.success?).to be true
    rsvp = Rsvp.find(result.value![:rsvp_id])
    expect(rsvp.attending).to be false
    expect(rsvp.attendance).to be_nil
  end

  describe "attendance dual-write (doc/attendances.md phase 2)" do
    before { DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 3) }

    def mirror
      Attendance.find_by_event_and_user(event[:id], user[:id])
    end

    it "mirrors a day-set rsvp into a going member attendance, dropping plus-ones" do
      membership = membership_for(user)
      attendance = [Date.today.iso8601, { "date" => (Date.today + 1).iso8601, "plusOnes" => 2 }]

      described_class.call(
        event_id: event[:id], membership: membership, user_id: user[:id],
        attending: true, attendance: attendance, rsvp_id: SecureRandom.uuid
      )

      expect(mirror.status).to eq("going")
      expect(mirror.days).to eq([Date.today, Date.today + 1])
      expect(mirror.created_by_user_id.to_s).to eq(user[:id])
    end

    it "mirrors whole-event and legacy-range rsvps" do
      membership = membership_for(user)
      described_class.call(
        event_id: event[:id], membership: membership, user_id: user[:id],
        attending: true, rsvp_id: SecureRandom.uuid
      )
      expect(mirror.days).to be_nil

      described_class.call(
        event_id: event[:id], membership: membership, user_id: user[:id],
        attending: true, start_date: (Date.today + 1).iso8601, end_date: (Date.today + 2).iso8601,
        rsvp_id: SecureRandom.uuid
      )
      expect(mirror.days).to eq([Date.today + 1, Date.today + 2])
    end

    it "updates the same mirrored row on decline" do
      membership = membership_for(user)
      described_class.call(
        event_id: event[:id], membership: membership, user_id: user[:id],
        attending: true, rsvp_id: SecureRandom.uuid
      )
      mirrored_id = mirror.id.to_s

      described_class.call(
        event_id: event[:id], membership: membership, user_id: user[:id],
        attending: false, rsvp_id: SecureRandom.uuid
      )

      expect(mirror.id.to_s).to eq(mirrored_id)
      expect(mirror.status).to eq("declined")
      expect(mirror.days).to be_nil
      expect(DB[:attendances].count).to eq(1)
    end

    it "blocks declining while the member hosts going guest attendances" do
      membership = membership_for(user)
      described_class.call(
        event_id: event[:id], membership: membership, user_id: user[:id],
        attending: true, rsvp_id: SecureRandom.uuid
      )
      guest_row = TestFactories.guest(workspace: workspace)
      TestFactories.attendance(event: event, guest: guest_row, host: user, status: "going")

      result = described_class.call(
        event_id: event[:id], membership: membership, user_id: user[:id],
        attending: false, rsvp_id: SecureRandom.uuid
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("You cannot decline while you have guests going on this event")
      expect(mirror.status).to eq("going")
    end
  end
end
