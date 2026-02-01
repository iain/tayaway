# typed: true
# frozen_string_literal: true

require "concurrent/atomic/read_write_lock"
require "listen"

module Reloading
  class Middleware
    def initialize(app, lock)
      @app = app
      @lock = lock
    end

    def call(env)
      @lock.with_read_lock do
        @app.call(env)
      end
    end
  end

  def self.new_lock
    Concurrent::ReadWriteLock.new
  end

  def self.start_listener(lock:, loader:, code_dirs:)
    listener = Listen.to(*code_dirs) do |_modified, _added, _removed|
      lock.with_write_lock do
        loader.reload
      end
    end
    listener.start
  end
end
