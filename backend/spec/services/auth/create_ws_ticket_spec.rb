# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::CreateWsTicket do
  it "returns failure when auth header is missing" do
    result = described_class.call(auth_header: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Authorization required")
    expect(result.failure.http_status).to eq(401)
  end

  it "returns failure for invalid session token" do
    result = described_class.call(auth_header: "Bearer invalid-token")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired session")
    expect(result.failure.http_status).to eq(401)
  end

  it "returns a JWT ticket for a valid session" do
    user = TestFactories.user
    session = TestFactories.session(user: user)

    result = described_class.call(auth_header: "Bearer #{session[:token]}")

    expect(result.success?).to be true
    expect(result.value![:ticket]).to be_a(String)

    # Verify the JWT can be decoded
    decoded = Auth::Token.decode_ws_ticket(result.value![:ticket])
    expect(decoded[:token]).to be_a(String)

    # Verify ticket was stored with hashed token
    expect(DB[:ws_tickets].where(user_id: user[:id]).count).to eq(1)
  end
end
