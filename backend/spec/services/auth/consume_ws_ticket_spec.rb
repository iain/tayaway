# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::ConsumeWsTicket do
  it "returns user_id for a valid ticket JWT" do
    user = TestFactories.user
    result = TestFactories.ws_ticket(user: user)
    jwt = Auth::Token.encode_ws_ticket(token: result.token)

    consume_result = described_class.call(ticket_jwt: jwt)

    expect(consume_result.success?).to be true
    expect(consume_result.value![:user_id].to_s).to eq(user[:id])

    # Verify ticket is marked as used
    updated = DB[:ws_tickets].where(user_id: user[:id]).first
    expect(updated[:used_at]).not_to be_nil
  end

  it "returns failure when ticket JWT is nil" do
    result = described_class.call(ticket_jwt: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Missing ticket")
    expect(result.failure.http_status).to eq(401)
  end

  it "returns failure for invalid JWT" do
    result = described_class.call(ticket_jwt: "not-a-jwt")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired ticket")
    expect(result.failure.http_status).to eq(401)
  end

  it "returns failure for expired JWT" do
    payload = { token: "sometoken", exp: (Time.now - 60).to_i }
    expired_jwt = JWT.encode(payload, APP_SECRET, "HS256")

    result = described_class.call(ticket_jwt: expired_jwt)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired ticket")
  end

  it "returns failure for already-used ticket" do
    user = TestFactories.user
    ticket_result = TestFactories.ws_ticket(user: user, used_at: Time.now)
    jwt = Auth::Token.encode_ws_ticket(token: ticket_result.token)

    result = described_class.call(ticket_jwt: jwt)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired ticket")
  end

  it "returns failure for non-existent ticket" do
    jwt = Auth::Token.encode_ws_ticket(token: "nonexistent")

    result = described_class.call(ticket_jwt: jwt)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired ticket")
  end
end
