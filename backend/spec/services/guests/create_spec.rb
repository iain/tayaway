# frozen_string_literal: true

require "spec_helper"

RSpec.describe Guests::Create do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: user)[:id]) }

  it "creates a guest under the client id" do
    client_id = SecureRandom.uuid

    result = described_class.call(workspace_id: workspace[:id], membership: membership, name: "Emma", guest_id: client_id)

    expect(result.value![:created]).to be true
    row = DB[:guests].where(id: client_id).first
    expect(row[:name]).to eq("Emma")
    expect(row[:workspace_id]).to eq(workspace[:id])
    expect(row[:placeholder]).to be false
    expect(row[:created_by_user_id]).to eq(user[:id])
  end

  it "is idempotent on replay and keeps the stored name" do
    client_id = SecureRandom.uuid
    described_class.call(workspace_id: workspace[:id], membership: membership, name: "Emma", guest_id: client_id)
    Guests::Rename.call(workspace_id: workspace[:id], membership: membership, guest_id: client_id, name: "Emma Jones")

    replay = described_class.call(workspace_id: workspace[:id], membership: membership, name: "Emma", guest_id: client_id)

    expect(replay.value![:created]).to be false
    expect(DB[:guests].where(id: client_id).get(:name)).to eq("Emma Jones")
    expect(DB[:guests].count).to eq(1)
  end

  it "validates the name" do
    blank = described_class.call(workspace_id: workspace[:id], membership: membership, name: " ", guest_id: SecureRandom.uuid)
    expect(blank.failure.message).to eq("Name is required")

    long = described_class.call(workspace_id: workspace[:id], membership: membership, name: "a" * 256, guest_id: SecureRandom.uuid)
    expect(long.failure.message).to eq("Name is too long (maximum 255 characters)")
  end

  it "refuses to claim an id that already exists in another workspace" do
    foreign = TestFactories.guest

    result = described_class.call(workspace_id: workspace[:id], membership: membership, name: "Emma", guest_id: foreign[:id])

    expect(result.failure.message).to eq("Guest is not part of this workspace")
  end

  it "returns failure for an unknown workspace" do
    result = described_class.call(workspace_id: SecureRandom.uuid, membership: membership, name: "Emma", guest_id: SecureRandom.uuid)

    expect(result.failure.message).to eq("Workspace not found")
  end
end
