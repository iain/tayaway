# frozen_string_literal: true

# falcon-host entry point. Loaded by `bin/falcon-host falcon.rb`.
#
# Each worker is a forked process that loads config.ru, so all application
# initialisation (Zeitwerk, mailer config, DB.server_version pre-cache) runs
# once per worker after fork rather than in the host. Pre-loading from the
# host would amortise that work via copy-on-write but is unsafe with libpq:
# any DB connect in the host poisons libpq state for forked children and
# segfaults their first Sequel.connect.

require "falcon/environment/rack"

service "web" do
  include Falcon::Environment::Rack

  # Pinned to one container until Listener/Keepalive move off OS threads.
  # See doc/falcon-architecture.md migration step 1.
  count 1

  url ENV.fetch("FALCON_URL", "http://localhost:9292")
end
