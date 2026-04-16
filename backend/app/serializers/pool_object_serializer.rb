# frozen_string_literal: true

# Shared defaults for per-type pool serializers. A serializer class defines
# at minimum `.serialize_batch(items, pool:)`. It can override
# `.policy_context_batch(items)` when its policy needs prefetched kwargs.
# `.policy_context(obj)` delegates to the batch form by default so serializers
# don't need to implement both.
#
# @example
#   class FooSerializer
#     extend PoolObjectSerializer
#
#     class << self
#       def serialize_batch(items, pool:) = ...
#       # policy_context_batch optional — default is {}
#     end
#   end
module PoolObjectSerializer
  def policy_context(obj)
    policy_context_batch([obj])[obj.id.to_s] || {}
  end

  def policy_context_batch(_items)
    {}
  end
end
