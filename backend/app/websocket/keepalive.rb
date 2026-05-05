# frozen_string_literal: true

require "async"

module Websocket
  # Background fiber that pings every connected WebSocket on a fixed interval
  # and prunes any that have not responded within the idle timeout.
  #
  # Runs as an Async task on the worker's reactor — one keepalive fiber per
  # forked worker process — so the cooperative sleep yields cleanly to
  # request-handling fibers between ticks.
  module Keepalive
    PING_INTERVAL = 30 # seconds between pings
    IDLE_TIMEOUT  = 90 # seconds before a connection is pruned

    class << self
      def run(connections: ConnectionManager.instance)
        APP_LOGGER.info { "[Keepalive] Started (interval=#{PING_INTERVAL}s, idle_timeout=#{IDLE_TIMEOUT}s)" }
        loop do
          Async::Task.current.sleep(PING_INTERVAL)
          tick(connections)
        end
      end

      def tick(connections = ConnectionManager.instance)
        pruned = connections.ping_all(idle_timeout: IDLE_TIMEOUT)
        APP_LOGGER.debug { "[Keepalive] Pruned #{pruned} stale connections" } if pruned > 0
      rescue StandardError => e
        APP_LOGGER.error { "[Keepalive] Error during ping: #{e.message}" }
      end
    end
  end
end
