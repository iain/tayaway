# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkspaceInvite do
  let(:workspace) { TestFactories.workspace }
  let(:inviter) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:invite_row) { TestFactories.workspace_invite(workspace: workspace, invited_by: inviter) }
      let(:pool_object) { described_class.serialize_batch([described_class.find(invite_row[:id])], pool: nil).first }

      it_behaves_like "a pool object with createdAt", "workspaceInvite"
    end

    it "serializes invite fields" do
      invite_row = TestFactories.workspace_invite(
        workspace: workspace, invited_by: inviter, email: "new@example.com", name: "Newbie"
      )
      invite = described_class.find(invite_row[:id])

      result = described_class.serialize_batch([invite], pool: nil).first

      expect(result[:id]).to eq(invite.id.to_s)
      expect(result[:objectType]).to eq("workspaceInvite")
      expect(result[:workspaceId]).to eq(workspace[:id].to_s)
      expect(result[:invitedBy]).to eq(inviter[:id].to_s)
      expect(result[:email]).to eq("new@example.com")
      expect(result[:name]).to eq("Newbie")
      expect(result[:expiresAt]).to match(/\.\d{3}/)
      expect(result[:acceptedAt]).to be_nil
    end
  end
end
