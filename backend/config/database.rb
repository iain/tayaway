# frozen_string_literal: true

require "sequel"

# Falcon runs concurrent request fibers on the same thread. Sequel's default
# pool keys connections by Thread.current, so fibers would share connections
# and corrupt each other's query results. This extension keys by Fiber.current.
# Skip in test env where DatabaseCleaner uses transaction strategy.
Sequel.extension :fiber_concurrency unless APP_CONFIG.test?

# Lazy database connection - defers connection until first use
# This is required for Falcon which forks after loading config.ru.
#
# Connection budget per worker: every long-running fiber that parks on
# `LISTEN` (Websocket::Listener in web workers, Jobs::Worker#wait_for_signal
# in jobs workers) holds one pool connection for the lifetime of the
# process. Effective request-pool size is therefore `max_connections - 1`.
# Keep that headroom in mind if the default ever drops or `count` rises:
# pods × DATABASE_POOL_SIZE (with one slot reserved per worker) must stay
# under PG's max_connections.
DB = Sequel.connect(
  APP_CONFIG.database_url,
  preconnect: false,
  test: false,
  max_connections: APP_CONFIG.database_pool_size,
  pool_timeout: 5,
  connect_timeout: 5,
  after_connect: proc { |conn| conn.exec("SET statement_timeout = '30s'") }
)

DB.extension :pg_json
DB.extension :pg_array
DB.extension :pg_inet

# Pre-cache the server version before Falcon forks workers.
# Under Falcon's fiber scheduler, the pg gem may return the version as a
# String instead of Integer, which breaks Sequel's generated SQL methods
# that compare `server_version >= 80400`. By resolving it here (outside the
# fiber scheduler), we get the correct Integer and then disconnect so forked
# workers create their own connections.
DB.server_version
DB.disconnect
