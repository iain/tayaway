# frozen_string_literal: true

module Websocket
  # Context for per-user permission computation during broadcasts.
  #
  # Carries the raw model objects AND the per-object policy kwargs (e.g.
  # event:, has_expenses:) that policies need but aren't in the serialized
  # JSON. Both are keyed by "<registry_key>:<id>" so every object in the
  # broadcast payload — including fan-out children pushed by parent
  # serializers — has its own entry and ships with correct permissions.
  PolicyContext = Struct.new(:raw_objects, :policy_contexts, keyword_init: true)
end
