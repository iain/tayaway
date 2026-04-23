# frozen_string_literal: true

require "spec_helper"

RSpec.describe Expenses::Revert do
  let(:workspace) { TestFactories.workspace }
  let(:creator) { TestFactories.user }
  let(:other) { TestFactories.user }
  let(:membership) do
    row = TestFactories.workspace_membership(workspace: workspace, user: creator)
    WorkspaceMembership.find(row[:id])
  end
  let(:other_membership) do
    row = TestFactories.workspace_membership(workspace: workspace, user: other)
    WorkspaceMembership.find(row[:id])
  end
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: creator)
    DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))
    DB[:events].where(id: e[:id]).first
  end

  # Create an expense, then settle it so it's eligible for revert.
  def create_and_settle_expense(amount: 30)
    TestFactories.rsvp(event: event, user: creator, attending: true) unless Rsvp.find_by_event_and_user(event[:id], creator[:id])
    TestFactories.rsvp(event: event, user: other, attending: true) unless Rsvp.find_by_event_and_user(event[:id], other[:id])
    expense_id = Expenses::Create.call(
      event_id: event[:id],
      membership: membership,
      workspace_id: workspace[:id],
      description: "Dinner",
      amount: amount,
      start_date: "2026-01-01",
      end_date: "2026-01-01"
    ).value![:objects].find { |o| o[:objectType] == "expense" }[:id]

    Settlements::Create.call(event_id: event[:id], membership: membership, workspace_id: workspace[:id])
    expense_id
  end

  it "creates a mirror-image expense linked to the original" do
    expense_id = create_and_settle_expense(amount: 30)

    result = described_class.call(
      expense_id: expense_id,
      membership: membership,
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    revert_row = DB[:expenses].where(reverts_expense_id: expense_id).first
    expect(revert_row).not_to be_nil
    expect(revert_row[:amount].to_f).to eq(-30.0)
    expect(revert_row[:user_id]).to eq(creator[:id])
    expect(revert_row[:description]).to start_with("Reverts:")
    expect(revert_row[:settlement_id]).to be_nil
  end

  it "copies participants and factors from the original" do
    expense_id = create_and_settle_expense(amount: 60)
    DB[:expense_participants].where(expense_id: expense_id).delete
    DB[:expense_participants].insert(id: SecureRandom.uuid, expense_id: expense_id, user_id: creator[:id], factor: 1, created_at: Time.now, updated_at: Time.now)
    DB[:expense_participants].insert(id: SecureRandom.uuid, expense_id: expense_id, user_id: other[:id], factor: 2, created_at: Time.now, updated_at: Time.now)

    described_class.call(expense_id: expense_id, membership: membership, workspace_id: workspace[:id])

    revert_row = DB[:expenses].where(reverts_expense_id: expense_id).first
    participants = ExpenseParticipant.for_expense(revert_row[:id]).sort_by(&:factor)
    expect(participants.map { |p| [p.user_id.to_s, p.factor] }).to eq(
      [[creator[:id].to_s, 1.0], [other[:id].to_s, 2.0]]
    )
  end

  it "refuses when the caller isn't the creator" do
    expense_id = create_and_settle_expense(amount: 30)

    result = described_class.call(
      expense_id: expense_id,
      membership: other_membership,
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
  end

  it "refuses to revert an unsettled expense — edit or delete it instead" do
    TestFactories.rsvp(event: event, user: creator, attending: true)
    unsettled_id = Expenses::Create.call(
      event_id: event[:id],
      membership: membership,
      workspace_id: workspace[:id],
      description: "Lunch",
      amount: 10,
      start_date: "2026-01-01",
      end_date: "2026-01-01"
    ).value![:objects].find { |o| o[:objectType] == "expense" }[:id]

    result = described_class.call(expense_id: unsettled_id, membership: membership, workspace_id: workspace[:id])
    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
  end

  it "refuses to revert a revert" do
    expense_id = create_and_settle_expense(amount: 30)
    described_class.call(expense_id: expense_id, membership: membership, workspace_id: workspace[:id])
    revert_id = DB[:expenses].where(reverts_expense_id: expense_id).get(:id)

    result = described_class.call(expense_id: revert_id, membership: membership, workspace_id: workspace[:id])
    expect(result.failure?).to be true
  end

  it "refuses to revert the same expense twice" do
    expense_id = create_and_settle_expense(amount: 30)
    described_class.call(expense_id: expense_id, membership: membership, workspace_id: workspace[:id])

    result = described_class.call(expense_id: expense_id, membership: membership, workspace_id: workspace[:id])
    expect(result.failure?).to be true
    expect(result.failure.message).to eq("This expense has already been reverted")
  end

  it "refuses to revert when the event has no dates" do
    expense_id = create_and_settle_expense(amount: 30)
    DB[:events].where(id: event[:id]).update(start_date: nil, end_date: nil)

    result = described_class.call(expense_id: expense_id, membership: membership, workspace_id: workspace[:id])
    expect(result.failure?).to be true
    expect(result.failure.message).to include("missing dates")
  end

  it "re-broadcasts the original so clients refresh its permissions" do
    expense_id = create_and_settle_expense(amount: 30)

    broadcast_ids = []
    allow(Broadcaster).to receive(:object_changed) do |_type, id, **_kw|
      broadcast_ids << id.to_s
    end

    described_class.call(expense_id: expense_id, membership: membership, workspace_id: workspace[:id])

    expect(broadcast_ids).to include(expense_id.to_s)
  end
end
