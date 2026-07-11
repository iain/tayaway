# frozen_string_literal: true

require "spec_helper"

# Minimal stand-in for a WebSocket connection object (T.untyped in production).
# Defined at top-level to satisfy RSpec/LeakyConstantDeclaration.
class FakeWsConnection
  attr_reader :written

  def initialize
    @written = []
    @closed = false
  end

  def write(msg)
    @written << msg
  end

  def close(_code = nil, _reason = nil)
    @closed = true
  end

  def closed?
    @closed
  end
end

RSpec.describe Websocket::MessageHandler do
  let(:connection) { FakeWsConnection.new }
  let(:connection_id) { SecureRandom.uuid }
  let(:user_id) { SecureRandom.uuid }

  describe ".handle" do
    context "when message type is ping" do
      it "writes a pong response" do
        allow(Websocket::ConnectionManager.instance).to receive(:update_last_pong).and_return(true)

        described_class.handle(connection, connection_id, user_id, { type: "ping" }.to_json)

        expect(connection.written).to include(include('"type":"pong"'))
      end

      it "treats the inbound ping as the liveness signal and bumps last_pong_at" do
        # The browser only ever sends `ping` — it never sends `pong`. So the
        # server-side keepalive's freshness check has to update last_pong_at
        # on the inbound ping, otherwise every connection gets pruned ~90s
        # after it opens.
        allow(Websocket::ConnectionManager.instance).to receive(:update_last_pong).and_return(true)

        described_class.handle(connection, connection_id, user_id, { type: "ping" }.to_json)

        expect(Websocket::ConnectionManager.instance).to have_received(:update_last_pong).with(connection_id)
      end

      it "closes the connection instead of ponging when it is no longer registered" do
        # A pruned-but-still-open socket must not receive a pong: the client
        # would keep trusting a connection that is subscribed to nothing and
        # never syncs. Closing makes the client reconnect and resync.
        described_class.handle(connection, connection_id, user_id, { type: "ping" }.to_json)

        expect(connection.closed?).to be(true)
        expect(connection.written).not_to include(include('"type":"pong"'))
      end
    end

    context "when message type is unknown" do
      it "writes an error response" do
        described_class.handle(connection, connection_id, user_id, { type: "unknown" }.to_json)

        expect(connection.written).to include(include('"type":"error"'))
      end
    end
  end
end
