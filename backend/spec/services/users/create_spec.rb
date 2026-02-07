# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Users::Create do
  it "returns failure when email is missing" do
    result = described_class.call(name: "Test", email: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Email is required")
  end

  it "returns failure when email already exists" do
    create(:user, email: "existing@example.com")

    result = described_class.call(name: "Test", email: "existing@example.com")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("A user with this email already exists")
    expect(result.failure.http_status).to eq(400)
  end

  it "creates user with name and returns success" do
    result = described_class.call(name: "New User", email: "new@example.com")

    expect(result.success?).to be true
    expect(result.value![:user_id]).to be_a(String)
    expect(result.value![:objects]).to be_an(Array)
    user = DB[:users].where(id: result.value![:user_id]).first
    expect(user[:email]).to eq("new@example.com")
    expect(user[:name]).to eq("New User")
    expect(DB[:users].where(email: "new@example.com").count).to eq(1)
  end

  it "creates user with nil name when name is empty" do
    result = described_class.call(name: "", email: "noname@example.com")

    expect(result.success?).to be true
    user = DB[:users].where(id: result.value![:user_id]).first
    expect(user[:name]).to be_nil
  end
end
