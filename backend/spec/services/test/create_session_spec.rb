# frozen_string_literal: true

require "spec_helper"

RSpec.describe Test::CreateSession do
  it "returns failure when email is missing" do
    result = described_class.call(email: nil, name: "Test")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Email is required")
  end

  it "creates new user and session when user does not exist" do
    result = described_class.call(email: "new@example.com", name: "New User")

    expect(result.success?).to be true
    expect(result.value![:session_token]).to be_a(String)
    expect(result.value![:user_id]).to be_a(String)
    user = DB[:users].where(id: result.value![:user_id]).first
    expect(user[:email]).to eq("new@example.com")
    expect(user[:name]).to eq("New User")
    expect(DB[:users].count).to eq(1)
    expect(DB[:sessions].count).to eq(1)
  end

  it "uses existing user and updates name when different" do
    TestFactories.user(email: "existing@example.com", name: "Old Name")

    result = described_class.call(email: "existing@example.com", name: "Updated Name")

    expect(result.success?).to be true
    user = DB[:users].where(id: result.value![:user_id]).first
    expect(user[:name]).to eq("Updated Name")
    expect(DB[:users].count).to eq(1)
    expect(DB[:sessions].count).to eq(1)
  end
end
