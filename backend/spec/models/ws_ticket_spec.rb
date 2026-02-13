# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe WsTicket do
  describe ".find_valid" do
    it "returns a ticket matching the hashed token" do
      user = TestFactories.user
      result = TestFactories.ws_ticket(user: user)

      ticket = described_class.find_valid(Auth::Token.digest(result.token))

      expect(ticket).not_to be_nil
      expect(ticket.user_id.to_s).to eq(user[:id])
    end

    it "returns nil for an expired ticket" do
      user = TestFactories.user
      result = TestFactories.ws_ticket(user: user, expires_at: Time.now - 60)

      ticket = described_class.find_valid(Auth::Token.digest(result.token))

      expect(ticket).to be_nil
    end

    it "returns nil for an already-used ticket" do
      user = TestFactories.user
      result = TestFactories.ws_ticket(user: user, used_at: Time.now)

      ticket = described_class.find_valid(Auth::Token.digest(result.token))

      expect(ticket).to be_nil
    end

    it "returns nil for a non-existent token" do
      ticket = described_class.find_valid(Auth::Token.digest("nonexistent"))

      expect(ticket).to be_nil
    end
  end
end
