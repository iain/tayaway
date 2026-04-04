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
      subject(:abilities) { described_class.new(event: event, user_id: owner[:id].to_s).abilities }

      it "allows all owner actions" do
        expect(abilities[:update]).to eq({ allowed: true })
        expect(abilities[:delete]).to eq({ allowed: true })
        expect(abilities[:create_poll]).to eq({ allowed: true })
        expect(abilities[:close_poll]).to eq({ allowed: true })
        expect(abilities[:reopen_poll]).to eq({ allowed: true })
        expect(abilities[:add_date_range]).to eq({ allowed: true })
        expect(abilities[:remove_date_range]).to eq({ allowed: true })
      end
    end

    context "when user is not the owner" do
      subject(:abilities) { described_class.new(event: event, user_id: other_user[:id].to_s).abilities }

      it "denies all owner actions with not_owner reason" do
        %i[update delete create_poll close_poll reopen_poll add_date_range remove_date_range].each do |ability|
          expect(abilities[ability]).to eq({ allowed: false, reason: "not_owner", hint: "hidden" })
        end
      end
    end

    context "when event has expenses" do
      subject(:abilities) do
        described_class.new(event: event, user_id: owner[:id].to_s)
                       .with_context(has_expenses: true)
                       .abilities
      end

      it "disables delete with has_expenses reason" do
        expect(abilities[:delete]).to eq({ allowed: false, reason: "has_expenses", hint: "disabled" })
      end

      it "still allows other owner actions" do
        expect(abilities[:update]).to eq({ allowed: true })
        expect(abilities[:create_poll]).to eq({ allowed: true })
      end
    end

    context "when event has settlements" do
      subject(:abilities) do
        described_class.new(event: event, user_id: owner[:id].to_s)
                       .with_context(has_settlements: true)
                       .abilities
      end

      it "disables delete with has_settlements reason" do
        expect(abilities[:delete]).to eq({ allowed: false, reason: "has_settlements", hint: "disabled" })
      end
    end

    context "when event has both expenses and settlements" do
      subject(:abilities) do
        described_class.new(event: event, user_id: owner[:id].to_s)
                       .with_context(has_expenses: true, has_settlements: true)
                       .abilities
      end

      it "disables delete with has_settlements reason (settlements checked first)" do
        expect(abilities[:delete]).to eq({ allowed: false, reason: "has_settlements", hint: "disabled" })
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
      policy = described_class.new(event: event, user_id: owner[:id].to_s)
      policy.with_context(has_expenses: true)
      result = policy.authorize!(:delete)
      expect(result.failure?).to be true
      expect(result.failure.message).to eq("has_expenses")
    end
  end
end
