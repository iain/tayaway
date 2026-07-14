# frozen_string_literal: true

require "spec_helper"

RSpec.describe Guest do
  let(:workspace) { TestFactories.workspace }

  it "finds a guest with its fields" do
    row = TestFactories.guest(workspace: workspace, name: "Emma", placeholder: true)
    guest = described_class.find(row[:id])

    expect(guest.name).to eq("Emma")
    expect(guest.placeholder).to be true
    expect(guest.workspace_id.to_s).to eq(workspace[:id])
  end

  it "lists a workspace's guests ordered by name" do
    TestFactories.guest(workspace: workspace, name: "Zoe")
    TestFactories.guest(workspace: workspace, name: "Anna")
    TestFactories.guest(name: "Elsewhere") # other workspace

    expect(described_class.for_workspace(workspace[:id]).map(&:name)).to eq(%w[Anna Zoe])
  end

  it "returns guests changed since a timestamp" do
    row = TestFactories.guest(workspace: workspace)

    expect(described_class.changed_since(workspace[:id], Time.now - 60).map { |g| g.id.to_s }).to eq([row[:id]])
    expect(described_class.changed_since(workspace[:id], Time.now + 60)).to be_empty
  end

  it "distinguishes gone from not found via deleted_items" do
    expect(described_class.find_result(SecureRandom.uuid).failure.http_status).to eq(404)

    tombstoned_id = SecureRandom.uuid
    DB[:deleted_items].insert(workspace_id: workspace[:id], object_type: "guest", object_id: tombstoned_id)
    expect(described_class.find_result(tombstoned_id).failure.http_status).to eq(410)
  end
end
