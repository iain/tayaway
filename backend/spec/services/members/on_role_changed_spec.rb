# frozen_string_literal: true

require "spec_helper"

RSpec.describe Members::OnRoleChanged do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }
    let(:user) { TestFactories.user }

    it "notifies the member whose role moved" do
      row = TestFactories.workspace_membership(workspace: workspace, user: user)
      member = WorkspaceMembership.find(row[:id])

      described_class.call(member: member, old_role: "member", new_role: "admin")

      n = DB[:notifications].where(user_id: user[:id], kind: "member_role_changed").first
      expect(n).not_to be_nil
      expect(n[:data]["title"]).to match(/admin/i)
    end

    it "is silent when the user has vanished" do
      row = TestFactories.workspace_membership(workspace: workspace, user: user)
      member = WorkspaceMembership.find(row[:id])
      DB[:users].where(id: user[:id]).delete

      described_class.call(member: member, old_role: "member", new_role: "admin")

      expect(DB[:notifications].count).to eq(0)
    end
  end
end
