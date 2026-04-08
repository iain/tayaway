# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Remaining policies" do
  let(:workspace) { TestFactories.workspace }
  let(:user_a) { TestFactories.user }
  let(:user_b) { TestFactories.user }
  let(:admin_user) { TestFactories.user }
  let(:membership_a) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: user_a, role: "member")[:id]) }
  let(:admin_membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: admin_user, role: "admin")[:id]) }
  let(:membership_b) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: user_b, role: "member")[:id]) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: user_a) }
  let(:event) { Event.find(event_row[:id]) }

  describe DatePollPolicy do
    let(:poll_row) { TestFactories.date_poll(event: event_row) }
    let(:poll) { DatePoll.find(poll_row[:id]) }

    it "allows event owner to close" do
      policy = described_class.new(poll, membership: membership_a, event: event)
      expect(policy.close).to be_success
    end

    it "rejects non-event-owner from closing" do
      policy = described_class.new(poll, membership: membership_b, event: event)
      expect(policy.close).to be_failure
      expect(policy.close.failure).to eq(:not_event_owner)
    end

    it "has correct ACTIONS" do
      expect(described_class::ACTIONS).to contain_exactly(:close, :reopen, :create_date_range)
    end
  end

  describe DateRangePolicy do
    let(:poll_row) { TestFactories.date_poll(event: event_row) }
    let(:range_row) { TestFactories.date_range(date_poll: poll_row) }
    let(:range) { DateRange.find(range_row[:id]) }

    it "allows event owner to delete" do
      policy = described_class.new(range, membership: membership_a, event: event)
      expect(policy.delete).to be_success
    end

    it "rejects non-event-owner from deleting" do
      policy = described_class.new(range, membership: membership_b, event: event)
      expect(policy.delete).to be_failure
    end

    it "has correct ACTIONS" do
      expect(described_class::ACTIONS).to contain_exactly(:delete, :create_vote)
    end
  end

  describe VotePolicy do
    let(:poll_row) { TestFactories.date_poll(event: event_row) }
    let(:range_row) { TestFactories.date_range(date_poll: poll_row) }
    let(:vote_row) { TestFactories.vote(date_range: range_row, user: user_a) }
    let(:vote) { Vote.find(vote_row[:id]) }

    it "allows vote creator to delete" do
      policy = described_class.new(vote, membership: membership_a)
      expect(policy.delete).to be_success
    end

    it "rejects non-creators" do
      policy = described_class.new(vote, membership: membership_b)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_creator)
    end
  end

  describe RsvpPolicy do
    let(:rsvp_row) { TestFactories.rsvp(event: event_row, user: user_a) }
    let(:rsvp) { Rsvp.find(rsvp_row[:id]) }

    it "allows rsvp creator to delete" do
      policy = described_class.new(rsvp, membership: membership_a)
      expect(policy.delete).to be_success
    end

    it "rejects non-creators" do
      policy = described_class.new(rsvp, membership: membership_b)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_creator)
    end
  end

  describe WorkspacePolicy do
    it "allows any member to create events" do
      policy = described_class.new(workspace, membership: membership_a)
      expect(policy.create_event).to be_success
    end

    it "allows admins to invite" do
      policy = described_class.new(workspace, membership: admin_membership)
      expect(policy.invite).to be_success
    end

    it "rejects members from inviting" do
      policy = described_class.new(workspace, membership: membership_a)
      expect(policy.invite).to be_failure
      expect(policy.invite.failure).to eq(:not_admin_or_owner)
    end

    it "has correct ACTIONS" do
      expect(described_class::ACTIONS).to contain_exactly(:create_event, :invite, :manage_members)
    end
  end

  describe WorkspaceInvitePolicy do
    it "allows admins to delete and remind" do
      policy = described_class.new(nil, membership: admin_membership)
      expect(policy.delete).to be_success
      expect(policy.remind).to be_success
    end

    it "rejects members" do
      policy = described_class.new(nil, membership: membership_a)
      expect(policy.delete).to be_failure
    end
  end

  describe ChoreRosterPolicy do
    let(:roster_row) { TestFactories.chore_roster(event: event_row, user: user_a) }
    let(:roster) { ChoreRoster.find(roster_row[:id]) }

    it "allows roster creator to delete" do
      policy = described_class.new(roster, membership: membership_a)
      expect(policy.delete).to be_success
    end

    it "allows any member to create chores" do
      policy = described_class.new(roster, membership: membership_b)
      expect(policy.create_chore).to be_success
    end

    it "has correct ACTIONS" do
      expect(described_class::ACTIONS).to contain_exactly(:edit, :delete, :create_chore)
    end
  end

  describe TaskListPolicy do
    it "allows any member to edit and delete" do
      task_list_row = TestFactories.task_list(workspace: workspace, user: user_a)
      task_list = TaskList.find(task_list_row[:id])
      policy = described_class.new(task_list, membership: membership_b)
      expect(policy.edit).to be_success
      expect(policy.delete).to be_success
      expect(policy.create_task_item).to be_success
    end
  end
end
