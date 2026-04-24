# frozen_string_literal: true

require "spec_helper"

RSpec.describe Expenses::Create do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:membership) do
    row = TestFactories.workspace_membership(workspace: workspace, user: user)
    WorkspaceMembership.find(row[:id])
  end
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  let(:valid_params) do
    {
      event_id: event[:id],
      membership: membership,
      workspace_id: workspace[:id],
      description: "Dinner",
      amount: 42.50,
      start_date: "2026-01-01",
      end_date: "2026-01-01"
    }
  end

  describe "input validation" do
    it "fails when description is nil" do
      result = described_class.call(**valid_params, description: nil)

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Description is required")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when description is empty" do
      result = described_class.call(**valid_params, description: "")

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Description is required")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when description exceeds 255 characters" do
      result = described_class.call(**valid_params, description: "a" * 256)

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Description is too long (maximum 255 characters)")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when amount is nil" do
      result = described_class.call(**valid_params, amount: nil)

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Amount must be greater than zero")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when amount is zero" do
      result = described_class.call(**valid_params, amount: 0.0)

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Amount must be greater than zero")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when amount is negative" do
      result = described_class.call(**valid_params, amount: -5.0)

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Amount must be greater than zero")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when amount exceeds 1,000,000" do
      result = described_class.call(**valid_params, amount: 1_000_001.0)

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Amount cannot exceed 1,000,000")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when start_date is nil" do
      result = described_class.call(**valid_params, start_date: nil)

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Start date and end date are required")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when end_date is empty" do
      result = described_class.call(**valid_params, end_date: "")

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Start date and end date are required")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when end_date is nil" do
      result = described_class.call(**valid_params, end_date: nil)

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Start date and end date are required")
      expect(result.failure.http_status).to eq(400)
    end
  end

  describe "event date range validation" do
    it "fails when expense start_date is before event start_date" do
      DB[:events].where(id: event[:id]).update(
        start_date: Date.parse("2026-01-10"),
        end_date: Date.parse("2026-01-20")
      )
      TestFactories.rsvp(event: event, user: user, attending: true)

      result = described_class.call(**valid_params, start_date: "2026-01-05", end_date: "2026-01-15")

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Expense dates must fall within event date range")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when expense end_date is after event end_date" do
      DB[:events].where(id: event[:id]).update(
        start_date: Date.parse("2026-01-10"),
        end_date: Date.parse("2026-01-20")
      )
      TestFactories.rsvp(event: event, user: user, attending: true)

      result = described_class.call(**valid_params, start_date: "2026-01-15", end_date: "2026-01-25")

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Expense dates must fall within event date range")
      expect(result.failure.http_status).to eq(400)
    end
  end

  it "fails when user has no RSVP for the event" do
    result = described_class.call(**valid_params)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("You must RSVP to this event before adding expenses")
    expect(result.failure.http_status).to eq(403)
  end

  it "fails when user has RSVP with attending: false" do
    TestFactories.rsvp(event: event, user: user, attending: false)

    result = described_class.call(**valid_params)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("You must RSVP to this event before adding expenses")
  end

  it "succeeds when user has RSVP with attending: true" do
    TestFactories.rsvp(event: event, user: user, attending: true)

    result = described_class.call(**valid_params)

    expect(result.success?).to be true
    expense = result.value![:objects].find { |o| o[:objectType] == "expense" }
    expect(expense[:description]).to eq("Dinner")
    expect(expense[:amount]).to eq(42.5)
  end

  describe "date validation" do
    it "fails when start_date is not in YYYY-MM-DD format" do
      result = described_class.call(**valid_params, start_date: "01/01/2026", end_date: "2026-01-01")

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Dates must be in YYYY-MM-DD format")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when end_date is not in YYYY-MM-DD format" do
      result = described_class.call(**valid_params, start_date: "2026-01-01", end_date: "January 5, 2026")

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Dates must be in YYYY-MM-DD format")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when start_date is after end_date" do
      result = described_class.call(**valid_params, start_date: "2026-01-05", end_date: "2026-01-01")

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Start date must be on or before end date")
    end
  end

  describe "participant_ids" do
    let(:alice) { TestFactories.user(name: "Alice") }
    let(:bob) { TestFactories.user(name: "Bob") }

    before do
      TestFactories.rsvp(event: event, user: user, attending: true)
    end

    it "creates expense_participants when participant_ids provided" do
      result = described_class.call(**valid_params, participant_ids: [alice[:id], bob[:id]])

      expect(result.success?).to be true
      participants = result.value![:objects].select { |o| o[:objectType] == "expenseParticipant" }
      expect(participants.length).to eq(2)
      expect(participants.map { |p| p[:userId] }).to contain_exactly(alice[:id], bob[:id])

      expense = result.value![:objects].find { |o| o[:objectType] == "expense" }
      expect(expense[:participantIds]).to match_array(participants.map { |p| p[:id] })
    end

    it "creates no participants when participant_ids is nil" do
      result = described_class.call(**valid_params, participant_ids: nil)

      expect(result.success?).to be true
      expense = result.value![:objects].find { |o| o[:objectType] == "expense" }
      expect(expense[:participantIds]).to eq([])
    end

    it "creates no participants when participant_ids is empty" do
      result = described_class.call(**valid_params, participant_ids: [])

      expect(result.success?).to be true
      expense = result.value![:objects].find { |o| o[:objectType] == "expense" }
      expect(expense[:participantIds]).to eq([])
    end

    it "fails when participant_ids contain invalid user IDs" do
      result = described_class.call(**valid_params, participant_ids: [SecureRandom.uuid])

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("One or more participant user IDs are invalid")
    end

    it "preserves participants on idempotent replay" do
      id = SecureRandom.uuid
      result1 = described_class.call(**valid_params, id: id, participant_ids: [alice[:id]])

      expect(result1.success?).to be true

      result2 = described_class.call(**valid_params, id: id, participant_ids: [alice[:id]])

      expect(result2.success?).to be true
      participants = result2.value![:objects].select { |o| o[:objectType] == "expenseParticipant" }
      expect(participants.length).to eq(1)
      expect(participants.first[:userId]).to eq(alice[:id])
    end

    it "accepts participants with explicit factors" do
      result = described_class.call(
        **valid_params,
        participants: [
          { user_id: alice[:id], factor: 2.0 },
          { user_id: bob[:id], factor: 0.5 }
        ]
      )

      expect(result.success?).to be true
      participants = result.value![:objects].select { |o| o[:objectType] == "expenseParticipant" }
      expect(participants.length).to eq(2)
      by_user = participants.to_h { |p| [p[:userId], p] }
      expect(by_user[alice[:id]][:factor]).to eq(2.0)
      expect(by_user[bob[:id]][:factor]).to eq(0.5)
    end

    it "defaults factor to 1 when participants omit it" do
      result = described_class.call(
        **valid_params,
        participants: [{ user_id: alice[:id] }]
      )

      expect(result.success?).to be true
      participant = result.value![:objects].find { |o| o[:objectType] == "expenseParticipant" }
      expect(participant[:factor]).to eq(1.0)
    end

    it "legacy participant_ids payload defaults factors to 1" do
      result = described_class.call(**valid_params, participant_ids: [alice[:id]])

      expect(result.success?).to be true
      participant = result.value![:objects].find { |o| o[:objectType] == "expenseParticipant" }
      expect(participant[:factor]).to eq(1.0)
    end

    it "rejects a factor below 0.5" do
      result = described_class.call(
        **valid_params,
        participants: [{ user_id: alice[:id], factor: 0.25 }]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Participant factor must be a multiple of 0.5 between 0.5 and 9.5")
    end

    it "rejects a factor above 9.5" do
      result = described_class.call(
        **valid_params,
        participants: [{ user_id: alice[:id], factor: 10.0 }]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Participant factor must be a multiple of 0.5 between 0.5 and 9.5")
    end

    it "rejects a factor that is not a multiple of 0.5" do
      result = described_class.call(
        **valid_params,
        participants: [{ user_id: alice[:id], factor: 1.37 }]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Participant factor must be a multiple of 0.5 between 0.5 and 9.5")
    end

    it "rejects non-hash entries in participants array" do
      result = described_class.call(
        **valid_params,
        participants: [{ user_id: alice[:id], factor: 1.0 }, "bob"]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Each participant must be an object with user_id")
    end

    it "rejects participant entries with blank user_id" do
      result = described_class.call(
        **valid_params,
        participants: [{ user_id: "", factor: 1.0 }]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Each participant must have a user_id")
    end

    it "rejects participant_ids with blank entries" do
      result = described_class.call(**valid_params, participant_ids: [""])

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Each participant must have a user_id")
    end

    it "caps participants at the configured maximum" do
      too_many = Array.new(ValidationLimits::PARTICIPANT_MAX + 1) { { user_id: SecureRandom.uuid, factor: 1.0 } }
      result = described_class.call(**valid_params, participants: too_many)

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Too many participants (maximum #{ValidationLimits::PARTICIPANT_MAX})")
    end

    it "prefers participants over participant_ids when both are given" do
      result = described_class.call(
        **valid_params,
        participant_ids: [bob[:id]],
        participants: [{ user_id: alice[:id], factor: 2.0 }]
      )

      expect(result.success?).to be true
      participants = result.value![:objects].select { |o| o[:objectType] == "expenseParticipant" }
      expect(participants.length).to eq(1)
      expect(participants.first[:userId]).to eq(alice[:id])
      expect(participants.first[:factor]).to eq(2.0)
    end
  end

  it "returns the existing expense when the client-provided id already exists" do
    TestFactories.rsvp(event: event, user: user, attending: true)
    client_id = SecureRandom.uuid
    now = Time.now

    DB[:expenses].insert(
      id: client_id,
      event_id: event[:id],
      user_id: user[:id],
      amount: 42.50,
      description: "Original",
      start_date: Date.parse("2026-01-01"),
      end_date: Date.parse("2026-01-01"),
      created_at: now,
      updated_at: now
    )

    result = described_class.call(**valid_params, id: client_id)

    expect(result.success?).to be true
    expense = result.value![:objects].find { |o| o[:objectType] == "expense" }
    expect(expense[:id]).to eq(client_id)
    # Conflict is a no-op: original description is preserved.
    expect(DB[:expenses].where(id: client_id).get(:description)).to eq("Original")
    expect(DB[:expenses].where(id: client_id).count).to eq(1)
  end
end
