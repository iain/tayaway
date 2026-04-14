# frozen_string_literal: true

# Attaches policy-computed permissions to a serialized object hash.
#
# This is the single code path for permission merging — used both at sync time
# (PoolSerializer) and at broadcast time (Websocket::ConnectionManager), so the
# two can never drift.
#
# @example
#   PermissionAttacher.call(
#     event_hash,
#     raw_object: event,
#     membership: membership,
#     policy_context: { has_expenses: true }
#   )
#   # => event_hash.merge(permissions: { edit: { allowed: true }, ... })
module PermissionAttacher
  class << self
    def call(hash, raw_object:, membership:, policy_context: {})
      return hash unless membership

      entry = ObjectRegistry::BY_CLIENT_TYPE[hash[:objectType]]
      return hash unless entry&.policy

      policy_class = Object.const_get(entry.policy)
      policy = policy_class.new(raw_object, membership: membership, **policy_context)
      hash.merge(permissions: policy.permissions)
    rescue StandardError => e
      APP_LOGGER.error do
        "[PermissionAttacher] Failed for #{hash[:objectType]}: #{e.class}: #{e.message}\n" \
          "#{e.backtrace&.first(5)&.join("\n")}"
      end
      hash
    end

    # Attaches permissions to every object in a broadcast message, using the
    # supplied policy context. Non-mutating. Returns a new message hash.
    #
    # @param message [Hash] broadcast message shaped as
    #   { type:, workspaceId:, action:, data: { objects: [...] } }
    # @param membership [WorkspaceMembership, nil] the recipient's membership
    # @param policy_context [Websocket::PolicyContext] raw_objects by key + kwargs
    def attach_to_message(message, membership, policy_context)
      return message unless membership

      objects = message[:data][:objects].map do |obj|
        entry = ObjectRegistry::BY_CLIENT_TYPE[obj[:objectType]]
        next obj unless entry&.policy

        raw_object = policy_context.raw_objects[entry.key]
        next obj unless raw_object

        call(obj, raw_object: raw_object, membership: membership, policy_context: policy_context.kwargs)
      end

      message.merge(data: message[:data].merge(objects: objects))
    end
  end
end
