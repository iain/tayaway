# frozen_string_literal: true

# Collects and serializes objects for pool-based API responses.
#
# Objects are deduplicated by type and id. Per-type serialization logic lives
# in app/serializers/<type>_serializer.rb — this class is just the coordinator.
# Alongside each serialized hash, the pool records the raw model instance and
# its policy_context kwargs so downstream code (broadcast, permission
# re-computation) has everything it needs without re-querying.
#
# @example
#   pool = PoolSerializer.new(membership: membership)
#   pool.add(:event, [event])
#   { objects: pool.to_a }
class PoolSerializer
  # Per-object bundle of (serialized payload, raw model, policy_context kwargs).
  # `payload` rather than `hash` so Struct#hash isn't accidentally shadowed.
  Slot = Struct.new(:payload, :raw_object, :policy_context, keyword_init: true)

  def initialize(workspace_id: nil, membership: nil, collect_policy_contexts: nil)
    @slots = {}
    @membership = membership
    @workspace_id = if membership
                      membership.workspace_id.to_s
                    else
                      workspace_id&.to_s
                    end
    # Collect contexts whenever somebody downstream will consume them: either
    # PoolSerializer itself (membership set → attach permissions inline) or
    # a broadcast caller that opts in so per-connection attachment works.
    @collect_policy_contexts = collect_policy_contexts.nil? ? !membership.nil? : collect_policy_contexts
  end

  # Dispatches to the serializer registered for `key` in ObjectRegistry.
  # `items` may be a single object or an array.
  def add(key, items)
    entry = ObjectRegistry::BY_KEY[key.to_s]
    raise ArgumentError, "Unknown object key: #{key.inspect}" unless entry

    add_batch(entry, Array(items))
  end

  def to_a
    @slots.values.map(&:payload)
  end

  # Raw model instances keyed by "<registry_key>:<id>", populated when
  # policy contexts are being collected. Used by Websocket::Listener to build
  # a PolicyContext that covers every object in the broadcast payload —
  # including fan-out children pushed by parent serializers — so that
  # per-connection permission attachment can't silently drop children.
  def raw_objects
    @slots.each_with_object({}) do |(key, slot), h|
      h[key] = slot.raw_object if slot.raw_object
    end
  end

  # Policy-context kwargs keyed by "<registry_key>:<id>". Same lifecycle as
  # `raw_objects`.
  def policy_contexts
    @slots.each_with_object({}) do |(key, slot), h|
      h[key] = slot.policy_context if slot.policy_context
    end
  end

  private

  def add_batch(entry, items)
    return 0 if items.empty?

    serializer = entry.serializer_class
    raise ArgumentError, "No serializer_class for #{entry.key}" unless serializer

    contexts = @collect_policy_contexts ? serializer.policy_context_batch(items) : {}
    hashes = serializer.serialize_batch(items, pool: self)
    unless hashes.length == items.length
      raise "#{serializer}#serialize_batch returned #{hashes.length} hashes for #{items.length} items " \
            "(contract: same length with nil for skipped entries)"
    end

    added = 0

    items.zip(hashes).each do |obj, hash|
      next unless hash

      slot_key = "#{entry.key}:#{obj.id}"
      next if @slots.key?(slot_key)

      context = contexts[obj.id.to_s] || {}
      final_hash = if @membership
                     PermissionAttacher.call(
                       hash,
                       raw_object: obj,
                       membership: @membership,
                       policy_context: context
                     )
                   else
                     hash
                   end

      @slots[slot_key] = Slot.new(
        payload: final_hash,
        raw_object: @collect_policy_contexts ? obj : nil,
        policy_context: @collect_policy_contexts ? context : nil
      )
      added += 1
    end

    added
  end
end
