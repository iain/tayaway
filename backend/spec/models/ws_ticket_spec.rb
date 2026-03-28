# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe WsTicket do
  describe ".find_valid" do
    it "returns a ticket matching the hashed token" do
      user = TestFactories.user
      session = TestFactories.session(user: user)
      result = TestFactories.ws_ticket(session: session)

      ticket = described_class.find_valid(Auth::Token.digest(result.token))

      expect(ticket).not_to be_nil
      expect(ticket.session_id.to_s).to eq(session[:id])
    end

    it "returns nil for an expired ticket" do
      result = TestFactories.ws_ticket(expires_at: Time.now - 60)

      ticket = described_class.find_valid(Auth::Token.digest(result.token))

      expect(ticket).to be_nil
    end

    it "returns nil for an already-used ticket" do
      result = TestFactories.ws_ticket(used_at: Time.now)

      ticket = described_class.find_valid(Auth::Token.digest(result.token))

      expect(ticket).to be_nil
    end

    it "returns nil for a non-existent token" do
      ticket = described_class.find_valid(Auth::Token.digest("nonexistent"))

      expect(ticket).to be_nil
    end
  end
end
