# frozen_string_literal: true

# Shared defaults for per-type pool serializers. A serializer class defines
# at minimum `.serialize_batch(items, pool:)`. It can override
# `.policy_context_batch(items)` when its policy needs prefetched kwargs.
# `.policy_context(obj)` delegates to the batch form by default so serializers
# don't need to implement both.
#
# Serializers also own broadcast-audience derivation via
# `broadcast_audiences_for(obj)`. The Listener calls this once per NOTIFY
# after loading the object, then dispatches to each returned audience.
# The default covers the common case (workspace-audience object with a
# `workspace_id` field); types whose model needs a join (date_range, vote,
# expense_participant, …) override the method, as do types that fan out
# to multiple audiences (member → workspace + user).
#
# @example
#   class FooSerializer
#     extend PoolObjectSerializer
#
#     class << self
#       def serialize_batch(items, pool:) = ...
#       # policy_context_batch optional — default is {}
#       # broadcast_audiences_for(obj) optional — default uses obj.workspace_id
#     end
#   end
module PoolObjectSerializer
  WS_AUD = ->(id) { { kind: "workspace", id: id.to_s } }
  USR_AUD = ->(id) { { kind: "user", id: id.to_s } }

  def policy_context(obj)
    policy_context_batch([obj])[obj.id.to_s] || {}
  end

  def policy_context_batch(_items)
    {}
  end

  def broadcast_audiences_for(obj)
    [WS_AUD.call(obj.workspace_id)]
  end
end
