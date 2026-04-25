# frozen_string_literal: true

# Append-only record of a service-level mutation attempt. Successful calls,
# policy denials, and validation failures are all logged so we can answer
# "who did what and was it allowed". See Auditable for how rows get written.
class AuditLogEntry
  OUTCOMES = %w[success denied error].freeze

  attr_reader :id, :actor_kind, :actor_user_id, :workspace_id, :service,
              :subject_type, :subject_id, :outcome, :error_code, :error_message,
              :action_params, :idempotency_key_hash, :request_id, :created_at

  def initialize(
    id:,
    actor_kind:,
    service:,
    outcome:,
    action_params:,
    created_at:,
    actor_user_id: nil,
    workspace_id: nil,
    subject_type: nil,
    subject_id: nil,
    error_code: nil,
    error_message: nil,
    idempotency_key_hash: nil,
    request_id: nil
  )
    @id = id
    @actor_kind = actor_kind
    @actor_user_id = actor_user_id
    @workspace_id = workspace_id
    @service = service
    @subject_type = subject_type
    @subject_id = subject_id
    @outcome = outcome
    @error_code = error_code
    @error_message = error_message
    @action_params = action_params
    @idempotency_key_hash = idempotency_key_hash
    @request_id = request_id
    @created_at = created_at
  end

  # Maximum serialised size for action_params. A runaway audit_context could
  # otherwise bloat the table fast — we'd rather drop the payload and log a
  # warning than store an unbounded blob.
  MAX_ACTION_PARAMS_BYTES = 4_096

  class << self
    def create(
      service:,
      outcome:,
      actor_kind:,
      action_params: {},
      actor_user_id: nil,
      workspace_id: nil,
      subject_type: nil,
      subject_id: nil,
      error_code: nil,
      error_message: nil,
      idempotency_key_hash: nil,
      request_id: nil
    )
      raise ArgumentError, "Unknown outcome #{outcome.inspect}" unless OUTCOMES.include?(outcome.to_s)

      payload = bounded_params(service, action_params)

      # Savepoint so a failed insert (constraint violation, missing column,
      # …) cannot poison an outer transaction that the caller may be in.
      # Without this a corrupt audit row would abort the caller's mutation
      # transaction even though we intend audit failures to be silent.
      DB.transaction(savepoint: true) do
        DB[:audit_log_entries].insert(
          actor_kind: actor_kind.to_s,
          actor_user_id: actor_user_id&.to_s,
          workspace_id: workspace_id&.to_s,
          service: service,
          subject_type: subject_type&.to_s,
          subject_id: subject_id&.to_s,
          outcome: outcome.to_s,
          error_code: error_code&.to_s,
          error_message: error_message,
          action_params: Sequel.pg_jsonb(payload),
          idempotency_key_hash: idempotency_key_hash,
          request_id: request_id,
          created_at: Time.now
        )
      end
    end

    def for_subject(subject_type, subject_id)
      DB[:audit_log_entries]
        .where(subject_type: subject_type.to_s, subject_id: subject_id.to_s)
        .order(Sequel.desc(:created_at))
        .all
    end

    def for_actor(actor_user_id)
      DB[:audit_log_entries]
        .where(actor_user_id: actor_user_id.to_s)
        .order(Sequel.desc(:created_at))
        .all
    end

    private

    # Cap the JSON payload so a misconfigured audit_context can't bloat the
    # table. Oversized payloads are dropped to a marker hash so the row still
    # records the outcome.
    def bounded_params(service, params)
      params = {} unless params.is_a?(Hash)
      json = JSON.dump(params)
      return params if json.bytesize <= MAX_ACTION_PARAMS_BYTES

      APP_LOGGER.warn do
        "[AuditLogEntry] action_params exceeded #{MAX_ACTION_PARAMS_BYTES} bytes for #{service} (#{json.bytesize} bytes); dropped"
      end
      { _truncated: true, _original_bytes: json.bytesize }
    end
  end
end
