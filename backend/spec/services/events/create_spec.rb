# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Create do
  it "returns failure when name is missing" do
    user = create(:user)

    result = described_class.call(user_id: user.id, name: nil, description: nil, date_ranges: [])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "creates event with date ranges and returns success" do
    user = create(:user)
    date_ranges = [
      { "start_date" => "2024-01-01", "end_date" => "2024-01-05" },
      { "start_date" => "2024-01-10", "end_date" => "2024-01-15" }
    ]

    result = described_class.call(
      user_id: user.id,
      name: "Team Meeting",
      description: "Weekly sync",
      date_ranges: date_ranges
    )

    expect(result.success?).to be true
    expect(result.value![:event][:name]).to eq("Team Meeting")
    expect(result.value![:event][:description]).to eq("Weekly sync")
    expect(result.value![:event][:date_ranges].length).to eq(2)
  end

  it "sets description to nil when empty" do
    user = create(:user)

    result = described_class.call(user_id: user.id, name: "Event", description: "", date_ranges: [])

    expect(result.success?).to be true
    expect(result.value![:event][:description]).to be_nil
  end
end
