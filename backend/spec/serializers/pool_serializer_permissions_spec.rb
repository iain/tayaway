# frozen_string_literal: true

require "spec_helper"

RSpec.describe "PoolSerializer permissions" do
  let(:workspace) { TestFactories.workspace }
  let(:owner) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:owner_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: owner) }
  let(:other_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }
  let(:event) { Event.find(event_row[:id]) }

  it "includes permissions for event owner" do
    membership = WorkspaceMembership.find(owner_membership_row[:id])
    pool = PoolSerializer.new(membership: membership)
    pool.add_event(event)

    event_obj = pool.to_a.find { |o| o[:objectType] == "event" }
    expect(event_obj[:permissions][:edit]).to eq({ allowed: true })
    expect(event_obj[:permissions][:delete]).to eq({ allowed: true })
  end

  it "includes permissions for non-owner" do
    membership = WorkspaceMembership.find(other_membership_row[:id])
    pool = PoolSerializer.new(membership: membership)
    pool.add_event(event)

    event_obj = pool.to_a.find { |o| o[:objectType] == "event" }
    expect(event_obj[:permissions][:edit]).to eq({ allowed: false, reason: "not_owner" })
  end

  it "omits permissions when no membership provided" do
    pool = PoolSerializer.new(workspace_id: workspace[:id])
    pool.add_event(event)

    event_obj = pool.to_a.find { |o| o[:objectType] == "event" }
    expect(event_obj).not_to have_key(:permissions)
  end

  it "denies delete when event has expenses" do
    membership = WorkspaceMembership.find(owner_membership_row[:id])
    now = Time.now
    DB[:expenses].insert(
      id: SecureRandom.uuid, event_id: event_row[:id], user_id: owner[:id],
      description: "Test", amount: 10.0, start_date: Date.today, end_date: Date.today,
      created_at: now, updated_at: now
    )

    pool = PoolSerializer.new(membership: membership)
    pool.add_event(event)

    event_obj = pool.to_a.find { |o| o[:objectType] == "event" }
    expect(event_obj[:permissions][:delete]).to eq({ allowed: false, reason: "has_expenses" })
    expect(event_obj[:permissions][:edit]).to eq({ allowed: true })
  end

  it "attaches permissions in batch methods" do
    membership = WorkspaceMembership.find(owner_membership_row[:id])
    event2_row = TestFactories.event(workspace: workspace, user: other_user)
    event2 = Event.find(event2_row[:id])

    pool = PoolSerializer.new(membership: membership)
    pool.add_events_batch([event, event2])

    objects = pool.to_a.select { |o| o[:objectType] == "event" }
    expect(objects.length).to eq(2)
    expect(objects.all? { |o| o.key?(:permissions) }).to be true

    owned = objects.find { |o| o[:id] == event.id.to_s }
    not_owned = objects.find { |o| o[:id] == event2.id.to_s }
    expect(owned[:permissions][:edit]).to eq({ allowed: true })
    expect(not_owned[:permissions][:edit]).to eq({ allowed: false, reason: "not_owner" })
  end

  it "attaches permissions to expenses" do
    membership = WorkspaceMembership.find(owner_membership_row[:id])
    now = Time.now
    expense_id = SecureRandom.uuid
    DB[:expenses].insert(
      id: expense_id, event_id: event_row[:id], user_id: owner[:id],
      description: "Test", amount: 10.0, start_date: Date.today, end_date: Date.today,
      created_at: now, updated_at: now
    )
    expense = Expense.find(expense_id)

    pool = PoolSerializer.new(membership: membership)
    pool.add_expense(expense)

    expense_obj = pool.to_a.find { |o| o[:objectType] == "expense" }
    expect(expense_obj[:permissions][:edit]).to eq({ allowed: true })
    expect(expense_obj[:permissions][:delete]).to eq({ allowed: true })
  end
end
