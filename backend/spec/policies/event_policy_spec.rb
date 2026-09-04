# frozen_string_literal: true

require "spec_helper"

RSpec.describe EventPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:owner) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:owner_membership) { TestFactories.workspace_membership(workspace: workspace, user: owner) }
  let(:other_membership) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }
  let(:event) { Event.find(event_row[:id]) }

  describe "#edit" do
    it "allows the event owner" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.edit).to be_success
    end

    it "rejects non-owners" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.edit).to be_failure
      expect(policy.edit.failure).to eq(:not_owner)
    end

    it "allows a workspace admin who isn't the event owner" do
      admin_membership = TestFactories.workspace_membership(workspace: workspace, user: other_user, role: "admin")
      policy = described_class.new(event, membership: WorkspaceMembership.find(admin_membership[:id]))
      expect(policy.edit).to be_success
    end

    it "allows a workspace owner who isn't the event owner" do
      workspace_owner_membership = TestFactories.workspace_membership(workspace: workspace, user: other_user, role: "owner")
      policy = described_class.new(event, membership: WorkspaceMembership.find(workspace_owner_membership[:id]))
      expect(policy.edit).to be_success
    end
  end

  describe "#delete" do
    it "allows the event owner" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.delete).to be_success
    end

    it "rejects non-owners" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_owner)
    end

    it "rejects when event has expenses" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]), has_expenses: true)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:has_expenses)
    end

    it "allows a workspace admin who isn't the event owner" do
      admin_membership = TestFactories.workspace_membership(workspace: workspace, user: other_user, role: "admin")
      policy = described_class.new(event, membership: WorkspaceMembership.find(admin_membership[:id]))
      expect(policy.delete).to be_success
    end

    it "still rejects a workspace admin when the event has expenses" do
      admin_membership = TestFactories.workspace_membership(workspace: workspace, user: other_user, role: "admin")
      policy = described_class.new(event, membership: WorkspaceMembership.find(admin_membership[:id]), has_expenses: true)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:has_expenses)
    end
  end

  describe "#create_poll" do
    it "allows the event owner" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.create_poll).to be_success
    end

    it "rejects non-owners" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.create_poll).to be_failure
    end

    it "allows a workspace admin who isn't the event owner" do
      admin_membership = TestFactories.workspace_membership(workspace: workspace, user: other_user, role: "admin")
      policy = described_class.new(event, membership: WorkspaceMembership.find(admin_membership[:id]))
      expect(policy.create_poll).to be_success
    end
  end

  describe "#permissions" do
    it "returns a hash of all actions" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]))
      perms = policy.permissions

      expect(perms.keys).to contain_exactly(
        :edit, :delete, :create_poll, :create_expense, :create_settlement,
        :create_attendance, :create_chore_roster
      )
      expect(perms[:edit]).to eq({ allowed: true })
    end
  end
end
