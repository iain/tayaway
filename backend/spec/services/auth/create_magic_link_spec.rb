# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::CreateMagicLink do
  it "returns failure when email is missing" do
    result = described_class.call(email: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Email is required")
  end

  it "returns success and creates magic link token for existing user" do
    user = TestFactories.user(email: "test@example.com")

    result = described_class.call(email: "test@example.com")

    expect(result.success?).to be true
    expect(result.value![:message]).to include("If an account exists")
    expect(DB[:magic_link_tokens].where(user_id: user[:id]).count).to eq(1)
  end

  it "generates a URL with a single JWT token parameter" do
    TestFactories.user(email: "test@example.com")
    allow(APP_LOGGER).to receive(:debug)

    described_class.call(email: "test@example.com")

    expect(APP_LOGGER).to have_received(:debug) do |&block|
      expect(block.call).to match(/auth\/verify\?token=eyJ/)
    end
  end

  it "returns success without creating token for non-existent user" do
    result = described_class.call(email: "nonexistent@example.com")

    expect(result.success?).to be true
    expect(result.value![:message]).to include("If an account exists")
    expect(DB[:magic_link_tokens].count).to eq(0)
  end
end
