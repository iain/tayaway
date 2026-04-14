# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkspaceSerializer do
  describe ".serialize_batch" do
    it "includes memberIds for each workspace" do
      workspace_row = TestFactories.workspace(name: "Team A")
      user = TestFactories.user
      membership_row = TestFactories.workspace_membership(workspace: workspace_row, user: user)
      workspace = Workspace.find(workspace_row[:id])

      result = described_class.serialize_batch([workspace], pool: nil).first

      expect(result[:id]).to eq(workspace.id.to_s)
      expect(result[:objectType]).to eq("workspace")
      expect(result[:name]).to eq("Team A")
      expect(result[:memberIds]).to include(membership_row[:id].to_s)
    end

    it "returns empty memberIds for a workspace with no members" do
      workspace_row = TestFactories.workspace
      workspace = Workspace.find(workspace_row[:id])

      result = described_class.serialize_batch([workspace], pool: nil).first

      expect(result[:memberIds]).to eq([])
    end
  end
end
