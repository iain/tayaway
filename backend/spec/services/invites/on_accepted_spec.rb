# frozen_string_literal: true

require "spec_helper"

RSpec.describe Invites::OnAccepted do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }
    let(:inviter) { TestFactories.user }
    let(:invitee) { TestFactories.user }

    def stored_invite(invited_by:)
      row = TestFactories.workspace_invite(
        workspace: workspace,
        invited_by: { id: invited_by },
        email: invitee[:email]
      )
      WorkspaceInvite.find(row[:id])
    end

    it "notifies the original inviter" do
      invite = stored_invite(invited_by: inviter[:id])

      described_class.call(invite: invite, invitee: User.find(invitee[:id]))

      expect(DB[:notifications].where(user_id: inviter[:id], kind: "workspace_invite_accepted").count).to eq(1)
    end

    it "is silent when the invite has no inviter recorded" do
      invite = stored_invite(invited_by: inviter[:id])
      DB[:workspace_invites].where(id: invite.id).update(invited_by: nil)
      invite = WorkspaceInvite.find(invite.id)

      described_class.call(invite: invite, invitee: User.find(invitee[:id]))

      expect(DB[:notifications].count).to eq(0)
    end
  end
end
