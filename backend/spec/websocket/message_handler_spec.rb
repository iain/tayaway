# frozen_string_literal: true

require "spec_helper"

# Minimal stand-in for a WebSocket connection object (T.untyped in production).
# Defined at top-level to satisfy RSpec/LeakyConstantDeclaration.
class FakeWsConnection
  attr_reader :written

  def initialize
    @written = []
  end

  def write(msg)
    @written << msg
  end
end

RSpec.describe Websocket::MessageHandler do
  let(:connection) { FakeWsConnection.new }
  let(:connection_id) { SecureRandom.uuid }
  let(:user_id) { SecureRandom.uuid }

  describe ".handle" do
    context "when message type is pong" do
      it "updates last_pong_at for the connection" do
        allow(Websocket::ConnectionManager.instance).to receive(:update_last_pong)

        described_class.handle(connection, connection_id, user_id, { type: "pong" }.to_json)

        expect(Websocket::ConnectionManager.instance).to have_received(:update_last_pong).with(connection_id)
      end

      it "does not write a response to the connection" do
        allow(Websocket::ConnectionManager.instance).to receive(:update_last_pong)

        described_class.handle(connection, connection_id, user_id, { type: "pong" }.to_json)

        expect(connection.written).to be_empty
      end
    end

    context "when message type is ping" do
      it "writes a pong response" do
        described_class.handle(connection, connection_id, user_id, { type: "ping" }.to_json)

        expect(connection.written).to include(include('"type":"pong"'))
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
