# frozen_string_literal: true

require "spec_helper"

RSpec.describe Workspaces::Update do
  let(:workspace) { TestFactories.workspace(name: "Alpha") }
  let(:owner) { TestFactories.user }
  let(:owner_membership) do
    WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: owner, role: "owner")[:id])
  end

  it "renames the workspace and changes its timezone" do
    result = described_class.call(
      workspace_id: workspace[:id], membership: owner_membership,
      name: "Alpha Renamed", timezone: "Pacific/Auckland"
    )

    expect(result).to be_success
    row = DB[:workspaces].where(id: workspace[:id]).first
    expect(row[:name]).to eq("Alpha Renamed")
    expect(row[:timezone]).to eq("Pacific/Auckland")
  end

  # PATCH semantics: the settings form saves one section at a time, so an
  # omitted field must not blank out what's stored.
  it "leaves omitted fields alone" do
    described_class.call(
      workspace_id: workspace[:id], membership: owner_membership, name: nil, timezone: "Pacific/Auckland"
    )

    row = DB[:workspaces].where(id: workspace[:id]).first
    expect(row[:name]).to eq("Alpha")
    expect(row[:timezone]).to eq("Pacific/Auckland")
  end

  it "refuses a plain member" do
    member = WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, role: "member")[:id])

    result = described_class.call(
      workspace_id: workspace[:id], membership: member, name: "Nope", timezone: nil
    )

    expect(result.failure.http_status).to eq(403)
    expect(DB[:workspaces].where(id: workspace[:id]).get(:name)).to eq("Alpha")
  end

  it "validates the name and the timezone" do
    blank = described_class.call(
      workspace_id: workspace[:id], membership: owner_membership, name: " ", timezone: nil
    )
    expect(blank.failure.message).to eq("Name is required")

    bad_zone = described_class.call(
      workspace_id: workspace[:id], membership: owner_membership, name: nil, timezone: "Mars/Olympus"
    )
    expect(bad_zone.failure.message).to eq("Unknown timezone")

    expect(DB[:workspaces].where(id: workspace[:id]).get(:name)).to eq("Alpha")
  end
end
