# frozen_string_literal: true

require "async"

module Websocket
  # Graceful-shutdown hook for web workers that hold WebSocket connections.
  #
  # falcon-host stops a worker with SIGINT, which async-container turns
  # into an Interrupt that cancels the reactor's tasks. A live WebSocket
  # wedges that cancellation: async-http wraps each request in
  # `Task#defer_stop` while the response body is being written, and a
  # websocket's upgrade body streams until the peer hangs up — so the
  # cancel is deferred indefinitely, the worker hangs, and falcon-host
  # (or podman, racing it at the same 10s) SIGKILLs it. systemd records
  # the resulting exit 137 as a unit failure and pages.
  #
  # So: intercept the stop signal before the reactor is interrupted,
  # close every registered websocket (clients get a GOING_AWAY frame and
  # reconnect immediately), let the read loops unwind, and only then ask
  # the scheduler to exit. The trap handler just writes to a self-pipe —
  # traps can't take the ConnectionManager mutex — and a reactor fiber
  # parked on the pipe does the actual work.
  module Shutdown
    SIGNALS = %w[INT TERM].freeze
    # One reactor tick is enough for the read loops to unwind once their
    # sockets close; the second sweep catches a connection that was
    # accepted while the first sweep ran.
    SETTLE_SECONDS = 0.1

    class << self
      def install(parent: Async::Task.current)
        reader, writer = IO.pipe

        previous = SIGNALS.to_h do |signal|
          handler = Signal.trap(signal) do
            writer.write_nonblock("!")
          rescue StandardError
            nil
          end
          [signal, handler]
        end

        parent.async(annotation: "websocket.shutdown") do
          reader.read(1)
          # Restore the stock handlers first so a second signal during the
          # drain falls through to the immediate-stop path.
          previous.each { |signal, handler| Signal.trap(signal, handler) }
          2.times do
            ConnectionManager.instance.close_all
            sleep(SETTLE_SECONDS)
          end
          Fiber.scheduler.interrupt
        end
      end
    end
  end
end
