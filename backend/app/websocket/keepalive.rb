# frozen_string_literal: true

require "async"

module Websocket
  # Background task that sends server-initiated pings to all WebSocket
  # connections and prunes any that have not responded within the idle timeout.
  #
  # Runs as an Async task on the same reactor as request handlers, so the
  # ping cycle yields cleanly to the rest of the worker.
  #
  # Ping interval: every 30 seconds.
  # Idle timeout:  90 seconds (3 missed pings before pruning).
  #
  # @example
  #   Keepalive.start  # must be called from inside an Async reactor
  #   Keepalive.stop
  class Keepalive
    PING_INTERVAL = 30 # seconds between pings
    IDLE_TIMEOUT  = 90 # seconds before a connection is pruned

    class << self
      def start
        return if @task

        parent = Async::Task.current?
        raise "Websocket::Keepalive.start must be called inside an Async reactor" unless parent

        # Spawning on the reactor pins the lifetime to the worker, not to
        # whichever fiber happened to call start.
        @task = parent.reactor.async do |task|
          task.annotate("Websocket::Keepalive")
          run_loop(task)
        end
        APP_LOGGER.info { "[Keepalive] Started (interval=#{PING_INTERVAL}s, idle_timeout=#{IDLE_TIMEOUT}s)" }
      end

      def stop
        return unless @task

        @task.stop
        @task = nil
        APP_LOGGER.info { "[Keepalive] Stopped" }
      end

      def running?
        !@task.nil? && !@task.finished?
      end

      private

      def run_loop(task)
        until task.stopped?
          task.sleep(PING_INTERVAL)
          break if task.stopped?

          tick
        end
      end

      def tick
        pruned = Websocket::ConnectionManager.instance.ping_all(idle_timeout: IDLE_TIMEOUT)
        APP_LOGGER.debug { "[Keepalive] Pruned #{pruned} stale connections" } if pruned > 0
      rescue StandardError => e
        APP_LOGGER.error { "[Keepalive] Error during ping: #{e.message}" }
      end
    end
  end
end
