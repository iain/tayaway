# frozen_string_literal: true

require "async"
require "async/barrier"
require "async/semaphore"
require "json"

module Websocket
  # Topic-based pub/sub registry for WebSocket connections.
  #
  # A connection subscribes to one or more Topic instances
  # (`Topic.workspace(id)` / `Topic.user(id)`); a broadcast names the
  # topic and fans out to every connection in it. The kind of audience
  # is carried as data on the Topic value object, not sniffed from a
  # string prefix.
  #
  # Each falcon-host worker is a forked process with one reactor and one
  # thread, so this singleton is only ever touched by fibers cooperatively
  # scheduled on that single thread — fiber boundaries already serialise
  # access. The mutex is kept as a cheap defensive guard (uncontended
  # futex, near-zero cost) in case anything ever sneaks a real OS thread
  # in here.
  class ConnectionManager
    include Singleton

    # Cap on per-broadcast / per-keepalive-tick fan-out fibers. Each child
    # does one `write` + `flush`, so a slow TCP receiver only stalls its
    # own fiber — other clients deliver in parallel. Sized well above
    # realistic per-topic connection counts but well below the Sequel pool
    # so writes never crowd request connections.
    WRITE_CONCURRENCY = 32

    def initialize
      @mutex = Mutex.new
      @connections = {}
      @topic_connections = {}
    end

    def register(websocket, user_id, session_id = nil)
      connection_id = SecureRandom.uuid
      uid = user_id.to_s
      total = 0
      @mutex.synchronize do
        @connections[connection_id] = Connection.new(
          id: connection_id,
          websocket: websocket,
          user_id: uid,
          session_id: session_id
        )
        total = @connections.size
      end
      APP_LOGGER.info { "[ConnectionManager] User #{uid} connected (conn: #{connection_id}, total: #{total})" }
      connection_id
    end

    def unregister(connection_id)
      user_id = nil
      total = nil
      @mutex.synchronize do
        connection = @connections.delete(connection_id)
        return unless connection

        user_id = connection.user_id
        connection.topics.each do |topic|
          subs = @topic_connections[topic]
          next unless subs

          subs.delete(connection_id)
          @topic_connections.delete(topic) if subs.empty?
        end
        total = @connections.size
      end
      APP_LOGGER.info { "[ConnectionManager] User #{user_id} disconnected (conn: #{connection_id}, total: #{total})" }
    end

    # Subscribe a connection to one or more topics. Idempotent — re-subscribing
    # to an existing topic is a no-op. Topics must be Topic instances; mixing
    # string and Topic keys would silently miss the hash lookup at broadcast.
    def subscribe(connection_id, *topics)
      return if topics.empty?

      validate_topics!(topics)

      @mutex.synchronize do
        connection = @connections[connection_id]
        return unless connection

        topics.each do |topic|
          next if connection.topics.include?(topic)

          connection.topics.add(topic)
          (@topic_connections[topic] ||= Set.new).add(connection_id)
        end
      end
    end

    # Unsubscribe a connection from one or more topics. Topics the connection
    # wasn't subscribed to are silently skipped.
    def unsubscribe(connection_id, *topics)
      return if topics.empty?

      validate_topics!(topics)

      @mutex.synchronize do
        connection = @connections[connection_id]
        return unless connection

        topics.each do |topic|
          next unless connection.topics.delete?(topic)

          subs = @topic_connections[topic]
          next unless subs

          subs.delete(connection_id)
          @topic_connections.delete(topic) if subs.empty?
        end
      end
    end

    def subscribed?(connection_id, topic)
      raise ArgumentError, "ConnectionManager#subscribed? requires a Topic, got #{topic.class}" unless topic.is_a?(Topic)

      @mutex.synchronize do
        connection = @connections[connection_id]
        return false unless connection

        connection.topics.include?(topic)
      end
    end

    # Replace the membership the connection holds for the given workspace.
    # Per-workspace because a connection is now subscribed to every workspace
    # the user belongs to, and the right membership for permission attachment
    # depends on which workspace a broadcast names.
    def set_membership(connection_id, workspace_id, membership)
      @mutex.synchronize do
        connection = @connections[connection_id]
        return unless connection

        if membership
          connection.memberships[workspace_id.to_s] = membership
        else
          connection.memberships.delete(workspace_id.to_s)
        end
      end
    end

    def update_last_pong(connection_id)
      @mutex.synchronize do
        connection = @connections[connection_id]
        connection&.last_pong_at = Time.now
      end
    end

    # Ping all connections and unregister those that have not responded within
    # the idle timeout. Returns the number of connections pruned.
    def ping_all(idle_timeout:)
      deadline = Time.now - idle_timeout
      stale_ids = []
      fresh = []

      @mutex.synchronize { @connections.dup }.each do |connection_id, connection|
        if connection.last_pong_at < deadline
          stale_ids << connection_id
        else
          fresh << [connection_id, connection]
        end
      end

      fan_out(fresh) do |connection_id, connection|
        connection.websocket.write({ type: "ping" }.to_json)
        connection.websocket.flush
      rescue StandardError => e
        APP_LOGGER.error { "[ConnectionManager] Error pinging conn #{connection_id}: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
        stale_ids << connection_id
      end

      stale_ids.each do |connection_id|
        APP_LOGGER.info { "[ConnectionManager] Pruning stale connection #{connection_id}" }
        unregister(connection_id)
      end

      stale_ids.size
    end

    # Broadcast a message to every connection subscribed to the topic.
    #
    # When `policy_context` is supplied AND `topic.workspace?`, permissions
    # are attached per-recipient using the membership that connection holds
    # for that workspace. User-topic broadcasts ignore the policy context —
    # the addressee is the audience, no per-viewer permission diff applies.
    def broadcast(topic, message, policy_context: nil)
      raise ArgumentError, "ConnectionManager#broadcast requires a Topic, got #{topic.class}" unless topic.is_a?(Topic)

      connection_ids = @mutex.synchronize { (@topic_connections[topic] || Set.new).to_a }
      return if connection_ids.empty?

      use_policy = policy_context && topic.workspace?
      json_message = message.to_json unless use_policy

      fan_out(connection_ids) do |connection_id|
        connection = @mutex.synchronize { @connections[connection_id] }
        next unless connection

        if use_policy
          membership = connection.memberships[topic.id]
          payload = attach_permissions(message, membership, policy_context).to_json
          send_to_connection(connection, connection_id, payload, topic)
        else
          send_to_connection(connection, connection_id, json_message, topic)
        end
      end
    end

    # Send a message directly to specific connections without going through
    # a topic. Used by the listener's new-workspace bootstrap to ship a
    # WorkspaceSync to the connections that just joined a workspace, before
    # the topic subscription is observable.
    def send_to_connections(connection_ids, message)
      return if connection_ids.empty?

      json_message = message.to_json

      fan_out(connection_ids) do |connection_id|
        connection = @mutex.synchronize { @connections[connection_id] }
        next unless connection

        send_to_connection(connection, connection_id, json_message, "direct")
      end
    end

    def connections_for_user(user_id)
      uid = user_id.to_s
      @mutex.synchronize do
        @connections.values.select { |c| c.user_id == uid }.map(&:id)
      end
    end

    # Send a session_revoked message and close all connections tied to the given session IDs.
    def close_sessions(session_ids)
      return if session_ids.empty?

      id_set = session_ids.to_set
      targets = @mutex.synchronize do
        @connections.values.select { |c| c.session_id && id_set.include?(c.session_id) }
      end

      message = { type: "session_revoked" }.to_json
      targets.each do |connection|
        begin
          connection.websocket.write(message)
          connection.websocket.flush
        rescue StandardError => e
          APP_LOGGER.error { "[ConnectionManager] Error sending session_revoked to conn #{connection.id}: #{e.class}: #{e.message}" }
        end
        unregister(connection.id)
      end

      APP_LOGGER.info { "[ConnectionManager] Closed #{targets.size} connection(s) for revoked sessions" } if targets.any?
    end

    def connection_count
      @mutex.synchronize { @connections.size }
    end

    private

    def validate_topics!(topics)
      bad = topics.reject { |t| t.is_a?(Topic) }
      return if bad.empty?

      raise ArgumentError, "ConnectionManager: topics must be Topic instances, got #{bad.map(&:class).uniq.inspect}"
    end

    # Run `block` against each item in `items` on its own fiber under a
    # bounded semaphore, awaiting all of them before returning. `Sync`
    # runs inline if a reactor is already current (the listener and
    # keepalive fibers) and spins one up otherwise (specs, ad-hoc calls).
    def fan_out(items)
      return if items.empty?

      Sync do
        barrier = Async::Barrier.new
        semaphore = Async::Semaphore.new(WRITE_CONCURRENCY, parent: barrier)
        items.each do |item|
          semaphore.async { yield(*item) }
        end
        barrier.wait
      end
    end

    def attach_permissions(message, membership, policy_context)
      PermissionAttacher.attach_to_message(message, membership, policy_context)
    end

    def send_to_connection(connection, connection_id, json_message, topic)
      connection.websocket.write(json_message)
      connection.websocket.flush
    rescue StandardError => e
      APP_LOGGER.error { "[ConnectionManager] Error broadcasting to #{topic}, conn #{connection_id}: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
      unregister(connection_id)
    end

    # Internal connection struct.
    class Connection
      attr_reader :id, :websocket, :user_id, :session_id, :topics, :memberships
      attr_accessor :last_pong_at

      def initialize(
        id:,
        websocket:,
        user_id:,
        session_id:,
        last_pong_at: Time.now
      )
        @id = id
        @websocket = websocket
        @user_id = user_id
        @session_id = session_id
        @topics = Set.new
        @memberships = {}
        @last_pong_at = last_pong_at
      end
    end
  end
end
