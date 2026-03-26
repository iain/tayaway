# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::CreateWsTicket do
  it "returns a JWT ticket for a valid user" do
    user = TestFactories.user

    session = TestFactories.session(user: user)
    result = described_class.call(user_id: user[:id], session_id: session[:id])

    expect(result.success?).to be true
    expect(result.value![:ticket]).to be_a(String)

    # Verify the JWT can be decoded
    decoded = Auth::Token.decode_ws_ticket(result.value![:ticket])
    expect(decoded[:token]).to be_a(String)

    # Verify ticket was stored with hashed token
    expect(DB[:ws_tickets].where(user_id: user[:id]).count).to eq(1)
  end
end
