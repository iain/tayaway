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
end
