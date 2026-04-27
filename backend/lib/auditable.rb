# frozen_string_literal: true

# Service-layer audit logging via an explicit block wrapper:
#
#   def call(event_id:, membership:, name:, **)
#     Auditable.around(
#       service: "Events::Update",
#       actor: membership,
#       subject_type: "event",
#       subject_id: event_id,
#       context: { name: name }
#     ) do
#       Event.find_result(event_id)
#            .bind { |event| EventPolicy.enforce(:edit, event, membership: membership) }
#            .bind { ... }
#     end
#   end
#
# The wrapper:
#   * runs the block,
#   * inspects the returned Result and writes one row with outcome
#     `success` / `denied` / `error` plus the error code and message,
#   * extracts the actor from the `actor:` argument (a WorkspaceMembership,
#     or nil for system-initiated calls),
#   * uses `subject_id` directly when given, or falls back to extracting
#     it from a pool-shaped success value (useful for create services
#     whose id is generated inside the block),
#   * suppresses inner cascaded calls so a service-of-services produces
#     one row at the outermost frame, via a fiber-local guard,
#   * never raises from the audit path itself: a failure to record an
#     audit row logs an error but does not corrupt the underlying
#     service result.
#
# A service that *raises* rather than returning a Failure is deliberately
# not audited — a raised mutation is a bug, not a user-attributable
# action, and wrapping every service in a transaction to record the
# raise would require restructuring all of them. Failures returned via
# the Result monad are audited normally.
module Auditable
  # Fiber storage (rather than Thread.current[], which is also fiber-local
  # but does not inherit into child fibers). The propagating semantics
  # matter under Falcon: if a service ever spawns work via Async {} the
  # child fiber should see the cascade flag and stay suppressed, otherwise
  # we'd record duplicate rows for the inner call.
  CASCADE_KEY = :auditable_in_progress
  private_constant :CASCADE_KEY

  class << self
    # `actor` is typically a WorkspaceMembership (responds to `user_id` and
    # `workspace_id`). Services operating outside a workspace context — user
    # profile edits, email change verification — pass `actor: nil` together
    # with an explicit `actor_user_id:` so the row still attributes the
    # action correctly.
    #
    # `context` is the curated dict that lands in `action_params`. The
    # subject row carries the canonical content (name, email, amount, …),
    # so the context only needs values that wouldn't be recoverable from
    # the subject after a future deletion. Email addresses, phone numbers,
    # and other directly-identifying personal data should not live here:
    # the audit table outlives the entities it points at, and putting that
    # data on the row makes it harder to honour deletion requests.
    # Identifiers (uuids), enum-like values (roles, response types, paid
    # flags), and short user-visible labels that double as moderation
    # signals (event names, chore names) are fine.
    def around(service:, actor:, actor_user_id: nil, subject_type: nil, subject_id: nil, workspace_id: nil, context: {})
      if Fiber[CASCADE_KEY]
        # Inner cascade: the outermost frame already owns the audit row.
        return yield
      end

      Fiber[CASCADE_KEY] = true
      begin
        result = yield
      ensure
        Fiber[CASCADE_KEY] = false
      end

      record(
        service: service,
        result: result,
        actor_user_id: actor_user_id || actor&.user_id,
        subject_type: subject_type,
        subject_id: subject_id || subject_id_from_result(result, subject_type),
        workspace_id: workspace_id || actor&.workspace_id,
        context: context
      )

      result
    end

    # Drop-in `.bind` step for services that load the subject inside the
    # chain and want the audit row to record whose record was acted on.
    # Mutates the shared `context` hash so the row reflects the lookup
    # without callers having to re-thread the subject out to where the
    # audit context was constructed.
    #
    #   .bind { |expense| Auditable.record_subject_user_id(audit_context, expense) }
    def record_subject_user_id(context, subject)
      context[:subject_user_id] = subject.user_id&.to_s
      Success(subject)
    end

    private

    def record(service:, result:, actor_user_id:, subject_type:, subject_id:, workspace_id:, context:)
      outcome, error_code, error_message = classify(result)

      AuditLogEntry.create(
        service: service,
        outcome: outcome,
        actor_kind: actor_user_id ? "user" : "system",
        actor_user_id: actor_user_id,
        workspace_id: workspace_id,
        subject_type: subject_type,
        subject_id: subject_id,
        error_code: error_code,
        error_message: error_message,
        action_params: context,
        idempotency_key_hash: RequestContext.idempotency_key_hash,
        request_id: RequestContext.request_id
      )
    rescue StandardError => e
      # Audit must never break the underlying request. We log loudly so
      # missing rows don't go unnoticed in dev/CI, then swallow.
      APP_LOGGER.error do
        "[Auditable] Failed to record audit row for #{service}: #{e.class}: #{e.message}"
      end
    end

    def classify(result)
      return ["success", nil, nil] if result.success?

      error = result.failure
      return ["error", nil, error.to_s] unless error.respond_to?(:code)

      outcome = error.code == :forbidden ? "denied" : "error"
      [outcome, error.code.to_s, error.message]
    end

    # Pull the first object of the configured subject_type out of a
    # pool-shaped success value, if present. Lets create services whose
    # id is generated inside the block produce the right subject_id
    # without callers having to thread it back out.
    def subject_id_from_result(result, subject_type)
      return nil unless subject_type
      return nil unless result.respond_to?(:success?) && result.success?

      value = result.value!
      return nil unless value.is_a?(Hash) && value[:objects].is_a?(Array)

      value[:objects].find { |o| o[:objectType] == subject_type }&.dig(:id)
    end
  end
end
