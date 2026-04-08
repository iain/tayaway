# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ObjectRegistry policy field" do
  it "maps every entry with a policy to a valid class" do
    ObjectRegistry::TYPES.each do |entry|
      next unless entry.policy

      policy_class = Object.const_get(entry.policy)
      expect(policy_class).to respond_to(:new), "#{entry.policy} should be a class"
      expect(policy_class.const_get(:ACTIONS)).to be_an(Array), "#{entry.policy} should have ACTIONS"
    end
  end

  it "includes policy for event" do
    expect(ObjectRegistry::BY_KEY["event"].policy).to eq("EventPolicy")
  end

  it "includes policy for settlement" do
    expect(ObjectRegistry::BY_KEY["settlement"].policy).to eq("SettlementPolicy")
  end
end
