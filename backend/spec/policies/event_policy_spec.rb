# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe EventPolicy do
  let(:owner) { TestFactories.user }
  let(:other_user) { TestFactories.user(email: "other@example.com") }
  let(:workspace) { TestFactories.workspace }
  let(:event_row) { TestFactories.event(workspace: workspace, user: owner) }
  let(:event) { Event.find(event_row[:id]) }

  describe "#abilities" do
    context "when user is the event owner" do
      subject(:abilities) do
        described_class.new(event: event, user_id: owner[:id].to_s).abilities
      end

      it "allows all owner actions" do
        %i[update delete create_poll close_poll reopen_poll add_date_range remove_date_range].each do |ability|
          expect(abilities[ability]).to be_a(BasePolicy::Allowed)
        end
      end
    end

    context "when user is not the owner" do
      subject(:abilities) do
        described_class.new(event: event, user_id: other_user[:id].to_s).abilities
      end

      it "denies all actions with not_owner reason" do
        %i[update delete create_poll close_poll reopen_poll add_date_range remove_date_range].each do |ability|
          expect(abilities[ability]).to be_a(BasePolicy::Denied)
          expect(abilities[ability].reason).to eq("not_owner")
          expect(abilities[ability].hint).to eq(BasePolicy::Hint::Hidden)
        end
      end
    end

    context "when event has expenses" do
      subject(:abilities) do
        context = described_class::Context.new(has_expenses: true)
        described_class.new(event: event, user_id: owner[:id].to_s, context: context).abilities
      end

      it "disables delete with has_expenses reason" do
        expect(abilities[:delete]).to be_a(BasePolicy::Denied)
        expect(abilities[:delete].reason).to eq("has_expenses")
        expect(abilities[:delete].hint).to eq(BasePolicy::Hint::Disabled)
      end

      it "still allows other owner actions" do
        expect(abilities[:update]).to be_a(BasePolicy::Allowed)
        expect(abilities[:create_poll]).to be_a(BasePolicy::Allowed)
      end
    end

    context "when event has settlements" do
      subject(:abilities) do
        context = described_class::Context.new(has_settlements: true)
        described_class.new(event: event, user_id: owner[:id].to_s, context: context).abilities
      end

      it "disables delete with has_settlements reason" do
        expect(abilities[:delete]).to be_a(BasePolicy::Denied)
        expect(abilities[:delete].reason).to eq("has_settlements")
        expect(abilities[:delete].hint).to eq(BasePolicy::Hint::Disabled)
      end
    end

    context "when event has both expenses and settlements" do
      subject(:abilities) do
        context = described_class::Context.new(has_expenses: true, has_settlements: true)
        described_class.new(event: event, user_id: owner[:id].to_s, context: context).abilities
      end

      it "disables delete with has_settlements reason (settlements checked first)" do
        expect(abilities[:delete].reason).to eq("has_settlements")
      end
    end
  end

  describe "#authorize!" do
    it "returns Success for allowed ability" do
      policy = described_class.new(event: event, user_id: owner[:id].to_s)
      result = policy.authorize!(:update)
      expect(result.success?).to be true
    end

    it "returns Failure for denied ability" do
      policy = described_class.new(event: event, user_id: other_user[:id].to_s)
      result = policy.authorize!(:update)
      expect(result.failure?).to be true
      expect(result.failure.code).to eq(:forbidden)
      expect(result.failure.message).to eq("not_owner")
    end

    it "returns Failure for denied delete with context" do
      context = described_class::Context.new(has_expenses: true)
      policy = described_class.new(event: event, user_id: owner[:id].to_s, context: context)
      result = policy.authorize!(:delete)
      expect(result.failure?).to be true
      expect(result.failure.message).to eq("has_expenses")
    end
  end

  describe "#abilities_api_hash" do
    it "serializes allowed abilities compactly" do
      api = described_class.new(event: event, user_id: owner[:id].to_s).abilities_api_hash
      expect(api[:update]).to eq({ allowed: true })
    end

    it "serializes denied abilities with reason and hint" do
      api = described_class.new(event: event, user_id: other_user[:id].to_s).abilities_api_hash
      expect(api[:update]).to eq({ allowed: false, reason: "not_owner", hint: "hidden" })
    end

    it "serializes disabled abilities with disabled hint" do
      context = described_class::Context.new(has_expenses: true)
      api = described_class.new(event: event, user_id: owner[:id].to_s, context: context).abilities_api_hash
      expect(api[:delete]).to eq({ allowed: false, reason: "has_expenses", hint: "disabled" })
    end
  end
end
