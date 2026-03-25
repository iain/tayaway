# typed: true
# frozen_string_literal: true

# Append-only audit log model. Records who changed what and when.
# Never update or delete rows — use for tracing mutations only.
class AuditLog < T::Struct
  extend T::Sig

  const :id, UUID
  const :user_id, T.nilable(UUID)
  const :action, String
  const :object_type, String
  const :object_id, UUID, without_accessors: true
  const :workspace_id, T.nilable(UUID)
  const :metadata, T.nilable(T::Hash[String, T.untyped])
  const :created_at, Time

  sig { returns(UUID) }
  def audit_object_id
    object_id
  end

  class << self
    extend T::Sig

    sig do
      params(
        user_id: T.nilable(T.any(String, UUID)),
        action: String,
        object_type: String,
        object_id: T.any(String, UUID),
        workspace_id: T.nilable(T.any(String, UUID)),
        metadata: T.nilable(T::Hash[String, T.untyped])
      ).void
    end
    def record(user_id:, action:, object_type:, object_id:, workspace_id:, metadata: nil)
      DB[:audit_logs].insert(
        user_id: user_id&.to_s,
        action: action,
        object_type: object_type,
        object_id: object_id.to_s,
        workspace_id: workspace_id&.to_s,
        metadata: metadata ? T.unsafe(Sequel).pg_jsonb(metadata) : nil,
        created_at: Time.now
      )
    rescue => e
      APP_LOGGER.error { "[AuditLog] Failed to record audit log: #{e.class}: #{e.message}" }
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:audit_logs].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(AuditLog) }
    def from_row(row)
      AuditLog.new(
        id: UUID.new(row[:id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        action: row[:action],
        object_type: row[:object_type],
        object_id: UUID.new(row[:object_id]),
        workspace_id: row[:workspace_id] ? UUID.new(row[:workspace_id]) : nil,
        metadata: row[:metadata],
        created_at: row[:created_at]
      )
    end
  end
end
