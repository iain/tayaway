# frozen_string_literal: true

require "spec_helper"

RSpec.describe Guests::Delete do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: user)[:id]) }

  it "deletes an unreferenced guest, leaving a tombstone" do
    row = TestFactories.guest(workspace: workspace)

    result = described_class.call(workspace_id: workspace[:id], membership: membership, guest_id: row[:id])

    expect(result.value![:deleted]).to eq([{ objectType: "guest", id: row[:id] }])
    expect(DB[:guests].where(id: row[:id]).count).to eq(0)
    tombstone = DB[:deleted_items].where(object_type: "guest", object_id: row[:id]).first
    expect(tombstone[:workspace_id]).to eq(workspace[:id])

    replay = described_class.call(workspace_id: workspace[:id], membership: membership, guest_id: row[:id])
    expect(replay.failure.http_status).to eq(410)
  end

  it "refuses to delete a guest with attendance rows" do
    event = TestFactories.event(workspace: workspace, user: user)
    row = TestFactories.guest(workspace: workspace)
    TestFactories.attendance(event: event, guest: row, host: user, status: "declined")

    result = described_class.call(workspace_id: workspace[:id], membership: membership, guest_id: row[:id])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("has_attendances")
    expect(result.failure.http_status).to eq(403)
    expect(DB[:guests].where(id: row[:id]).count).to eq(1)
  end

  it "rejects a guest from another workspace" do
    foreign = TestFactories.guest

    result = described_class.call(workspace_id: workspace[:id], membership: membership, guest_id: foreign[:id])

    expect(result.failure.message).to eq("Guest is not part of this workspace")
  end
end
