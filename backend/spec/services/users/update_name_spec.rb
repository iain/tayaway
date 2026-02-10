# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Users::UpdateName do
  it "returns failure when user tries to update another user" do
    user = TestFactories.user
    other_user = TestFactories.user

    result = described_class.call(
      user_id: other_user[:id],
      current_user_id: user[:id],
      name: "New Name"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Access denied")
    expect(result.failure.http_status).to eq(403)
  end

  it "returns failure when name is empty" do
    user = TestFactories.user

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: ""
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "returns failure when name is blank" do
    user = TestFactories.user

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "   "
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "updates user name" do
    user = TestFactories.user(name: "Original")

    result = described_class.call(
      user_id: user[:id],
      current_user_id: user[:id],
      name: "Updated Name"
    )

    expect(result.success?).to be true
    updated_user = result.value![:objects].find { |o| o[:objectType] == "user" }
    expect(updated_user[:name]).to eq("Updated Name")
  end
end
