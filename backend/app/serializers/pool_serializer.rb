# frozen_string_literal: true

# Collects and serializes objects for pool-based API responses.
# Objects are deduplicated by type and id. Per-type serialization logic lives
# in app/serializers/<type>_serializer.rb — this class is just the coordinator.
#
# @example
#   pool = PoolSerializer.new(membership: membership)
#   pool.add(:event, [event])
#   { objects: pool.to_a }
class PoolSerializer
  def initialize(workspace_id: nil, membership: nil)
    @objects = {}
    @membership = membership
    @workspace_id = if membership
                      membership.workspace_id.to_s
                    else
                      workspace_id&.to_s
                    end
  end

  # Dispatches to the serializer registered for `key` in ObjectRegistry.
  # `items` may be a single object or an array.
  def add(key, items)
    entry = ObjectRegistry::BY_KEY[key.to_s]
    raise ArgumentError, "Unknown object key: #{key.inspect}" unless entry

    add_batch(entry, Array(items))
  end

  def to_a
    @objects.values
  end

  private

  def add_batch(entry, items)
    return 0 if items.empty?

    serializer = entry.serializer_class
    raise ArgumentError, "No serializer_class for #{entry.key}" unless serializer

    contexts = serializer.policy_context_batch(items)
    hashes = serializer.serialize_batch(items, pool: self)
    unless hashes.length == items.length
      raise "#{serializer}#serialize_batch returned #{hashes.length} hashes for #{items.length} items " \
            "(contract: same length with nil for skipped entries)"
    end

    added = 0

    items.zip(hashes).each do |obj, hash|
      next unless hash

      key = "#{entry.key}:#{obj.id}"
      next if @objects.key?(key)

      @objects[key] = if @membership
                        PermissionAttacher.call(
                          hash,
                          raw_object: obj,
                          membership: @membership,
                          policy_context: contexts[obj.id.to_s] || {}
                        )
                      else
                        hash
                      end
      added += 1
    end

    added
  end
end
