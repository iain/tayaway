# frozen_string_literal: true

require "spec_helper"

RSpec.describe Workspaces::Create do
  let(:user) { TestFactories.user }

  it "creates the workspace with the caller as its owner" do
    result = described_class.call(user_id: user[:id], name: "Beta", timezone: "Europe/Lisbon")

    workspace = DB[:workspaces].where(id: result.value![:workspace_id]).first
    expect(workspace[:name]).to eq("Beta")
    expect(workspace[:timezone]).to eq("Europe/Lisbon")

    membership = DB[:workspace_memberships].where(workspace_id: workspace[:id], user_id: user[:id]).first
    expect(membership[:role]).to eq("owner")
  end

  it "falls back to the deployment's default timezone when none is given" do
    result = described_class.call(user_id: user[:id], name: "Beta", timezone: nil)

    expect(DB[:workspaces].where(id: result.value![:workspace_id]).get(:timezone)).to eq(Timezones::DEFAULT)
  end

  it "validates the name and the timezone" do
    blank = described_class.call(user_id: user[:id], name: " ", timezone: nil)
    expect(blank.failure.message).to eq("Name is required")

    long = described_class.call(user_id: user[:id], name: "a" * 256, timezone: nil)
    expect(long.failure.message).to eq("Name is too long (maximum 255 characters)")

    bad_zone = described_class.call(user_id: user[:id], name: "Beta", timezone: "Mars/Olympus")
    expect(bad_zone.failure.message).to eq("Unknown timezone")

    expect(DB[:workspaces].count).to eq(0)
  end

  # The command queue replays a create when the original response never made
  # it back, so the client id has to collapse the replay onto the first row
  # rather than leaving the user with two workspaces.
  it "is idempotent on replay of the client id" do
    client_id = SecureRandom.uuid

    first = described_class.call(user_id: user[:id], name: "Beta", timezone: nil, id: client_id)
    replay = described_class.call(user_id: user[:id], name: "Beta", timezone: nil, id: client_id)

    expect(first.value![:workspace_id]).to eq(client_id)
    expect(replay.value![:workspace_id]).to eq(client_id)
    expect(DB[:workspaces].count).to eq(1)
    expect(DB[:workspace_memberships].where(workspace_id: client_id).count).to eq(1)
  end

  it "refuses an id that already belongs to a workspace the caller is not in" do
    foreign = TestFactories.workspace

    result = described_class.call(user_id: user[:id], name: "Beta", timezone: nil, id: foreign[:id])

    expect(result.failure.message).to eq("Workspace already exists")
    expect(DB[:workspace_memberships].where(workspace_id: foreign[:id]).count).to eq(0)
  end
end
