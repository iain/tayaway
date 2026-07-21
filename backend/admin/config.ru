# typed: true
# frozen_string_literal: true

$stdout.sync = true

require_relative "../config/environment"

use RequestLogger

# No WebSocket listener, no job worker, no Rack::Attack — the admin site
# sits behind Caddy's mTLS gate and serves exactly one operator.
run AdminApp.freeze.app
