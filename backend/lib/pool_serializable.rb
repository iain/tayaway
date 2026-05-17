# frozen_string_literal: true

# Mixin for `Data.define`-backed pool object models that produces the
# wire shape consumed by PoolSerializer (and ultimately the frontend
# object pool) directly from `Data.members`, without a companion
# `<Type>Serializer` class.
#
# Field enumeration comes from the model's own `Data.define` signature,
# so the wire allowlist lives in exactly one place. Per-field formatting
# dispatches on the runtime value's Ruby class — UUID, EmailAddress,
# Time and Date all have unambiguous wire forms — so there is no
# schema reflection and no need for a per-field DSL in the common case.
#
# @example
#   class Vote < Data.define(:id, :date_range_id, :user_id, :response, ...)
#     include PoolSerializable
#     pool_object client_type: "vote"
#   end
#
#   Vote.serialize_batch([vote], pool: nil)
#   # => [{ id: "...", objectType: "vote", dateRangeId: "...", ... }]
#
# Sensitive columns (tokens, secrets) on the Data.define signature must
# be opted out explicitly:
#
#   class WorkspaceInvite < Data.define(..., :token, ...)
#     include PoolSerializable
#     pool_object client_type: "workspaceInvite"
#     pool_skip :token
#   end
module PoolSerializable
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def pool_object(client_type:)
      @pool_client_type = client_type
    end

    def pool_skip(*names)
      pool_skipped_fields.merge(names)
    end

    def pool_client_type
      @pool_client_type or raise "#{name} is PoolSerializable but missing `pool_object client_type: ...`"
    end

    def pool_skipped_fields
      @_pool_skipped_fields ||= Set.new
    end

    # Contract matches PoolSerializer's expectations
    # (see backend/app/serializers/pool_serializer.rb): given N items,
    # return N hashes. `pool:` is accepted for signature parity even
    # though the convention-based path never fans out children.
    def serialize_batch(items, pool: nil)
      items.map(&:to_pool_hash)
    end
  end

  def to_pool_hash
    hash = { id: id.to_s, objectType: self.class.pool_client_type }
    skipped = self.class.pool_skipped_fields
    self.class.members.each do |name|
      next if name == :id
      next if skipped.include?(name)

      hash[PoolSerializable.camel_key(name)] = PoolSerializable.format_value(public_send(name))
    end
    hash
  end

  # snake_case → lowerCamelCase. Plain regex, no ActiveSupport dependency.
  def self.camel_key(name)
    name.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }.to_sym
  end

  # Dispatches on the runtime value's class. Order matters: Time before
  # Date because `DateTime < Date` (we don't use DateTime today, but the
  # ordering keeps that future-proof); UUID/EmailAddress before the
  # else-branch so their `.to_s` wins over the default identity pass.
  def self.format_value(value)
    case value
    when nil                    then nil
    when UUID, EmailAddress     then value.to_s
    when Time                   then value.iso8601(3)
    when Date                   then value.iso8601
    else value
    end
  end
end
