# typed: true
# frozen_string_literal: true

require "json"

module Websocket
  # Singleton that tracks WebSocket connections and their channel subscriptions.
  # Thread-safe through mutex-protected operations.
  #
  # @example
  #   conn_id = ConnectionManager.instance.register(connection, user_id)
  #   ConnectionManager.instance.subscribe(conn_id, "event:uuid")
  #   ConnectionManager.instance.broadcast("event:uuid", { type: "update", data: {...} })
  #   ConnectionManager.instance.unregister(conn_id)
  class ConnectionManager
    extend T::Sig
    include Singleton

    sig { void }
    def initialize
      @mutex = Mutex.new
      @connections = T.let({}, T::Hash[String, Connection])
      @subscriptions = T.let({}, T::Hash[String, T::Set[String]])
    end

    sig { params(websocket: T.untyped, user_id: T.any(String, UUID)).returns(String) }
    def register(websocket, user_id)
      connection_id = SecureRandom.uuid
      @mutex.synchronize do
        @connections[connection_id] = Connection.new(
          id: connection_id,
          websocket: websocket,
          user_id: user_id.to_s,
          channels: Set.new
        )
      end
      connection_id
    end

    sig { params(connection_id: String, channel: String).void }
    def subscribe(connection_id, channel)
      @mutex.synchronize do
        connection = @connections[connection_id]
        return unless connection

        connection.channels.add(channel)
        @subscriptions[channel] ||= Set.new
        T.must(@subscriptions[channel]).add(connection_id)
      end
    end

    sig { params(connection_id: String, channel: String).void }
    def unsubscribe(connection_id, channel)
      @mutex.synchronize do
        connection = @connections[connection_id]
        return unless connection

        connection.channels.delete(channel)
        subs = @subscriptions[channel]
        return unless subs

        subs.delete(connection_id)
        @subscriptions.delete(channel) if subs.empty?
      end
    end

    sig { params(connection_id: String).void }
    def unregister(connection_id)
      @mutex.synchronize do
        connection = @connections.delete(connection_id)
        return unless connection

        connection.channels.each do |channel|
          subs = @subscriptions[channel]
          next unless subs

          subs.delete(connection_id)
          @subscriptions.delete(channel) if subs.empty?
        end
      end
    end

    sig { params(channel: String, message: T::Hash[Symbol, T.untyped]).void }
    def broadcast(channel, message)
      connection_ids = @mutex.synchronize { (@subscriptions[channel] || Set.new).to_a }
      json_message = message.to_json

      connection_ids.each do |connection_id|
        connection = @mutex.synchronize { @connections[connection_id] }
        next unless connection

        begin
          connection.websocket.write(json_message)
        rescue StandardError => e
          # Connection might be closed; log and continue
          warn "[ConnectionManager] Error broadcasting to #{connection_id}: #{e.message}"
        end
      end
    end

    sig { returns(Integer) }
    def connection_count
      @mutex.synchronize { @connections.size }
    end

    sig { returns(Integer) }
    def subscription_count
      @mutex.synchronize { @subscriptions.values.sum(&:size) }
    end

    # Internal connection struct
    class Connection < T::Struct
      const :id, String
      const :websocket, Object
      const :user_id, String
      prop :channels, T::Set[String], default: Set.new
    end
  end
end
