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
  end
end
