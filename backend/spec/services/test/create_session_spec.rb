# typed: false
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
    user = User.first(id: result.value![:user_id])
    expect(user.email).to eq("new@example.com")
    expect(user.name).to eq("New User")
    expect(User.count).to eq(1)
    expect(Session.count).to eq(1)
  end

  it "uses existing user and updates name when different" do
    create(:user, email: "existing@example.com", name: "Old Name")

    result = described_class.call(email: "existing@example.com", name: "Updated Name")

    expect(result.success?).to be true
    user = User.first(id: result.value![:user_id])
    expect(user.name).to eq("Updated Name")
    expect(User.count).to eq(1)
    expect(Session.count).to eq(1)
  end
end
