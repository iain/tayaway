# frozen_string_literal: true

# Rack::Test sessions advertise a supported protocol version by default,
# like any real client build — otherwise every route spec would trip the
# 426 gate now that MIN_SUPPORTED_VERSION has moved past 0. Per-request env
# headers win over this default, so the gate specs
# (spec/routes/client_version_spec.rb) can still exercise older and missing
# versions explicitly (`header "X-Client-Version", nil` clears it).
RSpec.configure do |config|
  config.before do
    # Guarded because a few specs shadow Rack::Test's `current_session` with
    # a `let` of their own (e.g. a sessions-table row); they make no rack
    # requests, so they don't need the default.
    session = current_session
    session.header("X-Client-Version", ClientProtocol::MIN_SUPPORTED_VERSION.to_s) if session.respond_to?(:header)
  end
end
