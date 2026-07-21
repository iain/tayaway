# frozen_string_literal: true

# falcon-host entry point for the admin site — a single web service, no
# jobs worker (the main falcon.rb owns that). Loaded by
# `bin/falcon-host admin/falcon.rb` from the backend root.

# See falcon.rb for why: falcon-host's notify pipe pokes the experimental
# IO::Buffer API, which warns on every load.
Warning[:experimental] = false

require "falcon/environment/rack"

# Resolved outside the service block — the block runs inside an
# Async::Service::Environment::Builder (BasicObject), which can't see
# Kernel#__dir__.
ADMIN_RACKUP_PATH = File.expand_path("config.ru", __dir__)

service "admin" do
  include Falcon::Environment::Rack

  count 1

  url ENV.fetch("ADMIN_FALCON_URL", "http://localhost:9393")
  endpoint { Async::HTTP::Endpoint.parse(url) }

  rackup_path ADMIN_RACKUP_PATH
end
