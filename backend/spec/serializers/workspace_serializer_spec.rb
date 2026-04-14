# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkspaceSerializer do
  describe ".serialize_batch" do
    context "when serializing a single object" do
      let(:workspace_row) { TestFactories.workspace }
      let(:pool_object) { described_class.serialize_batch([Workspace.find(workspace_row[:id])], pool: nil).first }

      subject { pool_object }

      it_behaves_like "a pool object with createdAt", "workspace"
    end

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
