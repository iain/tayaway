# frozen_string_literal: true

module Postgres
  # Park a fiber on a PG NOTIFY channel for the duration of a block.
  #
  # Borrows a connection from the pool, registers `LISTEN <channel>`
  # before yielding, and `UNLISTEN *` on exit — including on error or
  # fiber cancellation. The cleanup `UNLISTEN` is wrapped in a rescue:
  # if the connection itself died, the listen socket is already gone
  # and the cleanup query would only mask the original cause from the
  # caller's rescue.
  #
  # The caller decides how to actually park: a single
  # `wait_for_notify(timeout)` for "wake me on a signal", or a
  # `loop { wait_for_notify { … } }` for "process every payload as it
  # arrives". `pg` 1.3+ is fiber-scheduler-aware so `wait_for_notify`
  # yields the reactor while the socket has no data.
  #
  # The pooled connection must have its LISTEN registration cleared
  # before it goes back into the pool — otherwise a later borrower
  # would see stray notifications from this channel.
  module Listen
    class << self
      def subscribe(channel)
        DB.synchronize do |raw|
          raw.query("LISTEN #{channel}")
          begin
            yield raw
          ensure
            begin
              raw.query("UNLISTEN *")
            rescue StandardError
              # connection is already dead; nothing useful to clean up
            end
          end
        end
      end
    end
  end
end
