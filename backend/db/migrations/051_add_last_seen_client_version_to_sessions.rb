# frozen_string_literal: true

# Telemetry for the protocol version gate (doc/protocol-versioning.md):
# every authenticated API request records the PROTOCOL_VERSION its client
# advertised, so "can MIN_SUPPORTED_VERSION be raised past N?" is a query
# over active sessions instead of a guess. 0 means a client that sent no
# version header (pre-versioning build or non-app caller); NULL means the
# session hasn't made a request since this column shipped.
Sequel.migration do
  change do
    alter_table(:sessions) do
      add_column :last_seen_client_version, Integer, null: true
    end
  end
end
