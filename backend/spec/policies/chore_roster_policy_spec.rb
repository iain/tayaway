# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosterPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:event_owner) { TestFactories.user }
  let(:roster_creator) { TestFactories.user }
  let(:event_row) { TestFactories.event(workspace: workspace, user: event_owner) }
  let(:event) { Event.find(event_row[:id]) }
  let(:roster) { ChoreRoster.find(TestFactories.chore_roster(event: event_row, user: roster_creator)[:id]) }

  def membership_for(user, role: "member")
    row = TestFactories.workspace_membership(workspace: workspace, user: user, role: role)
    WorkspaceMembership.find(row[:id])
  end

  describe "#delete" do
    it "allows the roster creator" do
      policy = described_class.new(roster, membership: membership_for(roster_creator), event: event)
      expect(policy.delete).to be_success
    end

    it "allows the event owner even when a plain member" do
      policy = described_class.new(roster, membership: membership_for(event_owner), event: event)
      expect(policy.delete).to be_success
    end

    it "allows a workspace admin who neither created the roster nor owns the event" do
      policy = described_class.new(roster, membership: membership_for(TestFactories.user, role: "admin"), event: event)
      expect(policy.delete).to be_success
    end

    it "allows a workspace owner who neither created the roster nor owns the event" do
      policy = described_class.new(roster, membership: membership_for(TestFactories.user, role: "owner"), event: event)
      expect(policy.delete).to be_success
    end

    it "rejects a plain member who is not the creator or event owner" do
      policy = described_class.new(roster, membership: membership_for(TestFactories.user), event: event)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_creator)
    end

    it "fetches the event when not provided" do
      policy = described_class.new(roster, membership: membership_for(event_owner))
      expect(policy.delete).to be_success
    end
  end
end
