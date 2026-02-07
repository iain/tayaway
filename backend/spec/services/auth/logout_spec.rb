# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::Logout do
  it "returns failure when auth header is missing" do
    result = described_class.call(auth_header: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Authorization required")
    expect(result.failure.http_status).to eq(401)
  end

  it "destroys session and returns success" do
    user = create(:user)
    session = create(:session, user: user)

    result = described_class.call(auth_header: "Bearer #{session[:token]}")

    expect(result.success?).to be true
    expect(result.value![:message]).to eq("Logged out successfully")
    expect(DB[:sessions].where(id: session[:id]).count).to eq(0)
  end

  it "returns success even when session does not exist" do
    result = described_class.call(auth_header: "Bearer nonexistent")

    expect(result.success?).to be true
  end
end
