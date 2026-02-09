# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Create do
  it "returns failure when name is missing" do
    user = TestFactories.user
    workspace = TestFactories.workspace

    result = described_class.call(workspace_id: workspace[:id], user_id: user[:id], name: nil, description: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "creates event and returns success" do
    user = TestFactories.user
    workspace = TestFactories.workspace

    result = described_class.call(
      workspace_id: workspace[:id],
      user_id: user[:id],
      name: "Team Meeting",
      description: "Weekly sync"
    )

    expect(result.success?).to be true
    event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event[:name]).to eq("Team Meeting")
    expect(event[:description]).to eq("Weekly sync")
    expect(event[:datePollId]).to be_nil
  end

  it "sets description to nil when empty" do
    user = TestFactories.user
    workspace = TestFactories.workspace

    result = described_class.call(workspace_id: workspace[:id], user_id: user[:id], name: "Event", description: "")

    expect(result.success?).to be true
    event = result.value![:objects].find { |o| o[:objectType] == "event" }
    expect(event[:description]).to be_nil
  end
end
