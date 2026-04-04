# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExpensePolicy do
  let(:owner) { TestFactories.user }
  let(:other_user) { TestFactories.user(email: "other@example.com") }
  let(:workspace) { TestFactories.workspace }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }

  define_method(:create_expense) do |user_row: owner, settlement_id: nil|
    id = SecureRandom.uuid
    now = Time.now
    DB[:expenses].insert(
      id: id, event_id: event_row[:id], user_id: user_row[:id], settlement_id: settlement_id,
      description: "Dinner", amount: 20.0,
      start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 1),
      created_at: now, updated_at: now
    )
    T.must(Expense.find(id))
  end

  describe "#abilities" do
    context "when user is the owner and not settled" do
      it "allows update and delete" do
        expense = create_expense
        abilities = described_class.new(expense: expense, user_id: owner[:id].to_s).abilities
        expect(abilities[:update]).to be_a(BasePolicy::Allowed)
        expect(abilities[:delete]).to be_a(BasePolicy::Allowed)
      end
    end

    context "when user is not the owner" do
      it "denies with not_owner reason" do
        expense = create_expense
        abilities = described_class.new(expense: expense, user_id: other_user[:id].to_s).abilities
        expect(abilities[:update]).to be_a(BasePolicy::Denied)
        expect(abilities[:update].reason).to eq("not_owner")
      end
    end

    context "when expense is settled" do
      it "denies with is_settled reason even for the owner" do
        settlement_id = SecureRandom.uuid
        now = Time.now
        DB[:settlements].insert(
          id: settlement_id, event_id: event_row[:id], user_id: owner[:id],
          created_at: now, updated_at: now
        )
        expense = create_expense(settlement_id: settlement_id)
        abilities = described_class.new(expense: expense, user_id: owner[:id].to_s).abilities
        expect(abilities[:update]).to be_a(BasePolicy::Denied)
        expect(abilities[:update].reason).to eq("is_settled")
      end
    end
  end
end
