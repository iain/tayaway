# frozen_string_literal: true

require "spec_helper"

RSpec.describe Members::UpdateRole do
  let(:workspace) { TestFactories.workspace }
  let(:owner_user) { TestFactories.user(email: "owner@example.com") }
  let(:admin_user) { TestFactories.user(email: "admin@example.com") }
  let(:target_user) { TestFactories.user(email: "target@example.com") }

  let!(:owner_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: owner_user, role: "owner") }
  let!(:admin_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: admin_user, role: "admin") }
  let!(:target_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: target_user, role: "member") }

  let(:owner_membership) { WorkspaceMembership.find(owner_membership_row[:id]) }
  let(:admin_membership) { WorkspaceMembership.find(admin_membership_row[:id]) }

  it "returns failure for an invalid role" do
    result = described_class.call(
      membership: owner_membership,
      membership_id: target_membership_row[:id],
      new_role: "superadmin"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to include("Role must be one of")
  end

  it "returns failure when target member is not found" do
    result = described_class.call(
      membership: owner_membership,
      membership_id: SecureRandom.uuid,
      new_role: "admin"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Member not found")
  end

  it "returns failure when acting user is not a member of the workspace" do
    other_user = TestFactories.user(email: "other@example.com")
    other_workspace = TestFactories.workspace
    other_membership_row = TestFactories.workspace_membership(workspace: other_workspace, user: other_user, role: "member")
    other_membership = WorkspaceMembership.find(other_membership_row[:id])

    result = described_class.call(
      membership: other_membership,
      membership_id: target_membership_row[:id],
      new_role: "admin"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("not_admin_or_owner")
  end

  it "returns failure when acting user tries to change their own role" do
    result = described_class.call(
      membership: owner_membership,
      membership_id: owner_membership_row[:id],
      new_role: "admin"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("cannot_change_own_role")
  end

  context "when acting as owner" do
    it "can promote a member to admin" do
      result = described_class.call(
        membership: owner_membership,
        membership_id: target_membership_row[:id],
        new_role: "admin"
      )

      expect(result.success?).to be true
      updated = DB[:workspace_memberships].where(id: target_membership_row[:id]).first
      expect(updated[:role]).to eq("admin")
    end

    it "can promote a member to owner" do
      result = described_class.call(
        membership: owner_membership,
        membership_id: target_membership_row[:id],
        new_role: "owner"
      )

      expect(result.success?).to be true
    end

    it "can demote an admin to member" do
      result = described_class.call(
        membership: owner_membership,
        membership_id: admin_membership_row[:id],
        new_role: "member"
      )

      expect(result.success?).to be true
      updated = DB[:workspace_memberships].where(id: admin_membership_row[:id]).first
      expect(updated[:role]).to eq("member")
    end

    it "returns objects in the response" do
      result = described_class.call(
        membership: owner_membership,
        membership_id: target_membership_row[:id],
        new_role: "admin"
      )

      expect(result.success?).to be true
      expect(result.value![:objects]).to be_an(Array)
      expect(result.value![:objects].first[:objectType]).to eq("member")
    end
  end

  context "when acting as admin" do
    it "can promote a member to admin" do
      result = described_class.call(
        membership: admin_membership,
        membership_id: target_membership_row[:id],
        new_role: "admin"
      )

      expect(result.success?).to be true
    end

    it "can demote another admin to member" do
      other_admin = TestFactories.user(email: "admin2@example.com")
      other_admin_membership_row = TestFactories.workspace_membership(workspace: workspace, user: other_admin, role: "admin")

      result = described_class.call(
        membership: admin_membership,
        membership_id: other_admin_membership_row[:id],
        new_role: "member"
      )

      expect(result.success?).to be true
    end

    it "cannot change an owner's role" do
      result = described_class.call(
        membership: admin_membership,
        membership_id: owner_membership_row[:id],
        new_role: "member"
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("cannot_change_owner")
    end

    it "can promote a member to owner" do
      result = described_class.call(
        membership: admin_membership,
        membership_id: target_membership_row[:id],
        new_role: "owner"
      )

      expect(result.success?).to be true
      updated = DB[:workspace_memberships].where(id: target_membership_row[:id]).first
      expect(updated[:role]).to eq("owner")
    end
  end

  context "when acting as member" do
    let(:member_user) { TestFactories.user(email: "member@example.com") }
    let(:member_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: member_user, role: "member") }
    let(:member_membership) { WorkspaceMembership.find(member_membership_row[:id]) }

    before { member_membership }

    it "cannot change any roles" do
      result = described_class.call(
        membership: member_membership,
        membership_id: target_membership_row[:id],
        new_role: "admin"
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("not_admin_or_owner")
    end
  end
end
