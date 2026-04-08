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
  end

  describe "#permissions" do
    it "returns a hash of all actions" do
      policy = described_class.new(event, membership: WorkspaceMembership.find(owner_membership[:id]))
      perms = policy.permissions

      expect(perms.keys).to contain_exactly(
        :edit, :delete, :create_poll, :create_expense, :create_settlement,
        :create_rsvp, :create_chore_roster, :create_task_list
      )
      expect(perms[:edit]).to eq({ allowed: true })
    end
  end
end
