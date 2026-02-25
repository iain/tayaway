# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Expenses::Create do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  let(:valid_params) do
    {
      event_id: event[:id],
      user_id: user[:id],
      workspace_id: workspace[:id],
      description: "Dinner",
      amount: 42.50,
      start_date: "2026-01-01",
      end_date: "2026-01-01"
    }
  end

  it "fails when user has no RSVP for the event" do
    result = described_class.call(**valid_params)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("You must RSVP to this event before adding expenses")
    expect(result.failure.http_status).to eq(403)
  end

  it "fails when user has RSVP with attending: false" do
    TestFactories.rsvp(event: event, user: user, attending: false)

    result = described_class.call(**valid_params)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("You must RSVP to this event before adding expenses")
  end

  it "succeeds when user has RSVP with attending: true" do
    TestFactories.rsvp(event: event, user: user, attending: true)

    result = described_class.call(**valid_params)

    expect(result.success?).to be true
    expense = result.value![:objects].find { |o| o[:objectType] == "expense" }
    expect(expense[:description]).to eq("Dinner")
    expect(expense[:amount]).to eq(42.5)
  end
end
