# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::CreateWsTicket do
  it "returns a JWT ticket for a valid session" do
    user = TestFactories.user
    session = TestFactories.session(user: user)

    result = described_class.call(session_id: session[:id])

    expect(result.success?).to be true
    expect(result.value![:ticket]).to be_a(String)

    # Verify the JWT can be decoded
    decoded = Auth::Token.decode_ws_ticket(result.value![:ticket])
    expect(decoded[:token]).to be_a(String)

    # Verify ticket was stored with session_id
    ticket = DB[:ws_tickets].where(session_id: session[:id]).first
    expect(ticket).not_to be_nil
  end
end
