# typed: true
# frozen_string_literal: true

module Websocket
  # Background thread that sends server-initiated pings to all WebSocket
  # connections and prunes any that have not responded within the idle timeout.
  #
  # Ping interval: every 30 seconds.
  # Idle timeout:  90 seconds (3 missed pings before pruning).
  #
  # @example
  #   Keepalive.start  # Starts background thread
  #   Keepalive.stop   # Stops the thread
  class Keepalive
    extend T::Sig

    PING_INTERVAL = T.let(30, Integer) # seconds between pings
    IDLE_TIMEOUT  = T.let(90, Integer) # seconds before a connection is pruned

    class << self
      extend T::Sig

      sig { void }
      def start
        return if @running

        @running = true
        @thread = Thread.new { run_loop }
        @thread.abort_on_exception = true
        APP_LOGGER.info { "[Keepalive] Started (interval=#{PING_INTERVAL}s, idle_timeout=#{IDLE_TIMEOUT}s)" }
      end

      sig { void }
      def stop
        return unless @running

        @running = false
        @thread&.join(PING_INTERVAL + 1)
        @thread = nil
        APP_LOGGER.info { "[Keepalive] Stopped" }
      end

      sig { returns(T::Boolean) }
      def running?
        !!@running
      end

      private

      sig { void }
      def run_loop
        while @running
          # Sleep in small increments so stop wakes up quickly
          PING_INTERVAL.times do
            break unless T.unsafe(@running)

            sleep 1
          end

          next unless @running

          begin
            pruned = Websocket::ConnectionManager.instance.ping_all(idle_timeout: IDLE_TIMEOUT)
            APP_LOGGER.debug { "[Keepalive] Pinged all connections (pruned #{pruned} stale)" }
          rescue StandardError => e
            APP_LOGGER.error { "[Keepalive] Error during ping: #{e.message}" }
          end
        end
      end
    end
  end
end
