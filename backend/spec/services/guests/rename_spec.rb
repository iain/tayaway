# frozen_string_literal: true

require "spec_helper"

RSpec.describe Guests::Rename do
  let(:workspace) { TestFactories.workspace }
  let(:membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace)[:id]) }

  it "renames the guest and clears the placeholder flag" do
    row = TestFactories.guest(workspace: workspace, name: "Guest 1 (host)", placeholder: true)

    result = described_class.call(workspace_id: workspace[:id], membership: membership, guest_id: row[:id], name: "Emma")

    expect(result.success?).to be true
    updated = DB[:guests].where(id: row[:id]).first
    expect(updated[:name]).to eq("Emma")
    expect(updated[:placeholder]).to be false
  end

  it "validates the name" do
    row = TestFactories.guest(workspace: workspace)

    result = described_class.call(workspace_id: workspace[:id], membership: membership, guest_id: row[:id], name: "")

    expect(result.failure.message).to eq("Name is required")
  end

  it "rejects a guest from another workspace" do
    foreign = TestFactories.guest

    result = described_class.call(workspace_id: workspace[:id], membership: membership, guest_id: foreign[:id], name: "Emma")

    expect(result.failure.message).to eq("Guest is not part of this workspace")
  end

  it "returns not found for an unknown guest" do
    result = described_class.call(workspace_id: workspace[:id], membership: membership, guest_id: SecureRandom.uuid, name: "Emma")

    expect(result.failure.http_status).to eq(404)
  end
end
