# frozen_string_literal: true

require "spec_helper"

RSpec.describe MemberPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:owner_user) { TestFactories.user }
  let(:admin_user) { TestFactories.user }
  let(:member_user) { TestFactories.user }
  let(:target_user) { TestFactories.user }
  let(:owner_row) { TestFactories.workspace_membership(workspace: workspace, user: owner_user, role: "owner") }
  let(:admin_row) { TestFactories.workspace_membership(workspace: workspace, user: admin_user, role: "admin") }
  let(:member_row) { TestFactories.workspace_membership(workspace: workspace, user: member_user, role: "member") }
  let(:target_member_row) { TestFactories.workspace_membership(workspace: workspace, user: target_user, role: "member") }

  def membership(row)
    WorkspaceMembership.find(row[:id])
  end

  describe "#change_role" do
    it "allows owner to change any member's role" do
      policy = described_class.new(membership(target_member_row), membership: membership(owner_row))
      expect(policy.change_role).to be_success
    end

    it "allows admin to change member's role" do
      policy = described_class.new(membership(target_member_row), membership: membership(admin_row))
      expect(policy.change_role).to be_success
    end

    it "prevents admin from changing owner's role" do
      policy = described_class.new(membership(owner_row), membership: membership(admin_row))
      expect(policy.change_role).to be_failure
      expect(policy.change_role.failure).to eq(:cannot_change_owner)
    end

    it "prevents member from changing any role" do
      policy = described_class.new(membership(target_member_row), membership: membership(member_row))
      expect(policy.change_role).to be_failure
      expect(policy.change_role.failure).to eq(:not_admin_or_owner)
    end

    it "prevents changing own role" do
      policy = described_class.new(membership(owner_row), membership: membership(owner_row))
      expect(policy.change_role).to be_failure
      expect(policy.change_role.failure).to eq(:cannot_change_own_role)
    end
  end

  describe "#available_roles" do
    it "returns all roles for owner" do
      policy = described_class.new(membership(target_member_row), membership: membership(owner_row))
      expect(policy.available_roles).to eq(%w[member admin owner])
    end

    it "returns member and admin for admin" do
      policy = described_class.new(membership(target_member_row), membership: membership(admin_row))
      expect(policy.available_roles).to eq(%w[member admin])
    end

    it "returns empty for member" do
      policy = described_class.new(membership(target_member_row), membership: membership(member_row))
      expect(policy.available_roles).to eq([])
    end

    it "returns empty when changing own role" do
      policy = described_class.new(membership(owner_row), membership: membership(owner_row))
      expect(policy.available_roles).to eq([])
    end
  end

  describe "#permissions" do
    it "includes availableRoles in the permissions hash" do
      policy = described_class.new(membership(target_member_row), membership: membership(owner_row))
      perms = policy.permissions

      expect(perms[:change_role]).to eq({ allowed: true })
      expect(perms[:availableRoles]).to eq(%w[member admin owner])
    end
  end
end
