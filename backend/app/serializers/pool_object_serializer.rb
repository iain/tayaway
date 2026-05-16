# frozen_string_literal: true

# Shared defaults for per-type pool serializers. A serializer class defines
# at minimum `.serialize_batch(items, pool:)`. It can override
# `.policy_context_batch(items)` when its policy needs prefetched kwargs.
# `.policy_context(obj)` delegates to the batch form by default so serializers
# don't need to implement both.
#
# Serializers also own broadcast-topic derivation via `topics_for(obj)`.
# The Listener calls this once per NOTIFY after loading the object and
# dispatches to each returned topic. Topics are strings:
#   "workspace:<id>"  → workspace audience
#   "user:<id>"       → user audience
# The default covers the common case (object with a `workspace_id`
# field); types whose model needs a join (date_range, vote,
# expense_participant, …) override the method.
#
# @example
#   class FooSerializer
#     extend PoolObjectSerializer
#
#     class << self
#       def serialize_batch(items, pool:) = ...
#       # policy_context_batch optional — default is {}
#       # topics_for(obj) optional — default returns ["workspace:#{obj.workspace_id}"]
#     end
#   end
module PoolObjectSerializer
  def policy_context(obj)
    policy_context_batch([obj])[obj.id.to_s] || {}
  end

  def policy_context_batch(_items)
    {}
  end

  def topics_for(obj)
    ["workspace:#{obj.workspace_id}"]
  end
end
