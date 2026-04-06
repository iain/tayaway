# frozen_string_literal: true

require "spec_helper"

RSpec.describe DatePolls::AddDateRange do
  it "returns failure when user is not the event owner" do
    owner = TestFactories.user
    other_user = TestFactories.user
    event = TestFactories.event(user: owner)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: other_user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
  end

  it "returns failure when poll is not open" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event, closed_at: Time.now)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Poll is not open for changes")
  end

  it "returns failure when dates are invalid" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-10",
      end_date: "2024-06-01"
    )

    expect(result.failure?).to be true
  end

  it "adds a date range to the poll" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10"
    )

    expect(result.success?).to be true
    date_range = result.value![:objects].find { |o| o[:objectType] == "dateRange" }
    expect(date_range).not_to be_nil
    expect(date_range[:datePollId]).to eq(date_poll[:id])
    expect(DB[:date_ranges].where(date_poll_id: date_poll[:id]).count).to eq(1)
  end

  it "uses client-provided id when given" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event)
    client_id = SecureRandom.uuid

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10",
      id: client_id
    )

    expect(result.success?).to be true
    date_range = result.value![:objects].find { |o| o[:objectType] == "dateRange" }
    expect(date_range[:id]).to eq(client_id)
  end

  it "returns existing date range on idempotent replay with same id" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    TestFactories.date_poll(event: event)
    client_id = SecureRandom.uuid

    result1 = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10",
      id: client_id
    )
    result2 = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10",
      id: client_id
    )

    expect(result1.success?).to be true
    expect(result2.success?).to be true
    expect(DB[:date_ranges].where(id: client_id).count).to eq(1)
  end

  it "handles TOCTOU race: returns existing date range when concurrent insert wins" do
    user = TestFactories.user
    event = TestFactories.event(user: user)
    date_poll = TestFactories.date_poll(event: event)
    client_id = SecureRandom.uuid

    # Pre-insert a date range with this ID (simulates concurrent request that won the race)
    TestFactories.date_range(id: client_id, date_poll: date_poll)
    existing_date_range = DateRange.find(client_id)

    # Simulate the TOCTOU race: the early idempotency check sees nil (the race window),
    # so the service proceeds to insert and hits UniqueConstraintViolation.
    allow(DateRange).to receive(:find).with(client_id).and_return(nil, existing_date_range)

    result = described_class.call(
      event_id: event[:id],
      current_user_id: user[:id],
      start_date: "2024-06-01",
      end_date: "2024-06-10",
      id: client_id
    )

    expect(result.success?).to be true
    date_range = result.value![:objects].find { |o| o[:objectType] == "dateRange" }
    expect(date_range[:id]).to eq(client_id)
    expect(DB[:date_ranges].where(id: client_id).count).to eq(1)
  end
end
