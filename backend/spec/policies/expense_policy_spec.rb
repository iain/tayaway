# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExpensePolicy do
  let(:workspace) { TestFactories.workspace }
  let(:owner) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:owner_membership) { TestFactories.workspace_membership(workspace: workspace, user: owner) }
  let(:other_membership) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }

  def create_settlement
    now = Time.now
    id = SecureRandom.uuid
    DB[:settlements].insert(id: id, event_id: event_row[:id], user_id: owner[:id], created_at: now, updated_at: now)
    id
  end

  def create_expense(user:, settled: false)
    settlement_id = settled ? create_settlement : nil
    now = Time.now
    id = SecureRandom.uuid
    DB[:expenses].insert(
      id: id, event_id: event_row[:id], user_id: user[:id],
      description: "Test", amount: 10.0,
      start_date: Date.today, end_date: Date.today,
      settlement_id: settlement_id,
      created_at: now, updated_at: now
    )
    Expense.find(id)
  end

  describe "#edit" do
    it "allows the expense creator" do
      expense = create_expense(user: owner)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.edit).to be_success
    end

    it "rejects non-creators" do
      expense = create_expense(user: owner)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.edit).to be_failure
      expect(policy.edit.failure).to eq(:not_creator)
    end

    it "rejects when expense is settled" do
      expense = create_expense(user: owner, settled: true)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.edit).to be_failure
      expect(policy.edit.failure).to eq(:settled)
    end
  end

  describe "#delete" do
    it "allows the expense creator" do
      expense = create_expense(user: owner)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.delete).to be_success
    end

    it "rejects when settled even for creator" do
      expense = create_expense(user: owner, settled: true)
      policy = described_class.new(expense, membership: WorkspaceMembership.find(owner_membership[:id]))
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:settled)
    end
  end
end
