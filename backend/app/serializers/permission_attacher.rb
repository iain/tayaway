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
    # Real policy bugs (NoMethodError, ArgumentError, Sequel::DatabaseError, …)
    # propagate to the caller — sync returns 500, broadcast's per-object rescue
    # in `attach_to_message` logs and skips the one bad object. The only
    # exception we rescue locally is a genuinely-expected NameError from
    # const_get when a registry entry points at a class that isn't loaded.
    def call(hash, raw_object:, membership:, policy_context: {})
      return hash unless membership

      entry = ObjectRegistry::BY_CLIENT_TYPE[hash[:objectType]]
      return hash unless entry&.policy

      policy_class = resolve_policy_class(entry.policy, hash, membership)
      return hash unless policy_class

      policy = policy_class.new(raw_object, membership: membership, **policy_context)
      hash.merge(permissions: policy.permissions)
    end

    # Attaches permissions to every object in a broadcast message, using the
    # supplied policy context. Non-mutating. Returns a new message hash.
    #
    # A crash computing permissions for one object is caught here so it does
    # not take down the whole broadcast for every recipient. The affected
    # object ships without a `permissions` key and the failure is logged with
    # enough context (object id, membership id, backtrace) to diagnose.
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

        begin
          call(obj, raw_object: raw_object, membership: membership, policy_context: policy_context.kwargs)
        rescue StandardError => e
          APP_LOGGER.error do
            "[PermissionAttacher] Broadcast permission failure for #{obj[:objectType]} " \
              "id=#{obj[:id]} membership=#{membership.id}: #{e.class}: #{e.message}\n" \
              "#{e.backtrace&.first(5)&.join("\n")}"
          end
          obj
        end
      end

      message.merge(data: message[:data].merge(objects: objects))
    end

    private

    def resolve_policy_class(name, hash, membership)
      Object.const_get(name)
    rescue NameError => e
      APP_LOGGER.error do
        "[PermissionAttacher] Unknown policy class #{name.inspect} for " \
          "#{hash[:objectType]} id=#{hash[:id]} membership=#{membership.id}: #{e.message}"
      end
      nil
    end
  end
end
