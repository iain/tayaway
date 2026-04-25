# frozen_string_literal: true

# Service-layer audit logging. Opted-in services get every `.call` recorded
# to `audit_log_entries`, including denied attempts and validation failures,
# so we can answer "who did what and was it allowed" after the fact.
#
# Usage in a service module:
#
#   module Events
#     module Update
#       extend Auditable
#       audit subject_type: "event"
#
#       class << self
#         def call(event_id:, membership:, **) ... end
#
#         def audit_context(event_id:, **)
#           { event_id: event_id }
#         end
#       end
#     end
#   end
#
# The wrapper:
#   * runs the underlying `.call`,
#   * extracts the actor from `membership:` (or treats it as a system call if
#     no membership was passed),
#   * asks the service for `audit_context(**kwargs)` — a curated dict to
#     persist as `action_params` (optional; defaults to `{}`),
#   * detects the subject id either from `audit_subject_id(**kwargs, result:)`
#     or, by default, from the kwargs key matching the configured subject_type
#     (e.g. `event_id` when subject_type is "event"),
#   * collapses cascaded inner service calls into the outermost row via a
#     thread-local guard,
#   * never raises from the audit path itself: a failure to record an audit
#     row logs a warning but does not corrupt the underlying service result.
module Auditable
  # Falcon runs this app on fibers, so per-request state must live in fiber
  # storage — Thread.current would let two fibers on the same thread see and
  # clobber each other's flags, suppressing audit rows or attributing them
  # to the wrong actor under load.
  CASCADE_KEY = :auditable_in_progress

  # Configure how this service is audited. Called once at module load time.
  #
  # @param subject_type [String, nil] the subject_type column value, e.g. "event"
  def audit(subject_type: nil)
    @audit_subject_type = subject_type
    singleton_class.prepend(Hook) unless singleton_class.include?(Hook)
  end

  def audit_subject_type
    @audit_subject_type
  end

  # Default action_params if the service doesn't override it. Empty so we
  # never accidentally serialise raw kwargs (which can contain PII).
  def audit_context(**)
    {}
  end

  # Default subject id resolution: look for `<subject_type>_id` in the
  # kwargs, then fall back to `id`. Services can override for richer logic
  # (e.g. resolving the subject from the result on creates).
  def audit_subject_id(result:, **kwargs)
    return nil unless audit_subject_type

    key = :"#{audit_subject_type}_id"
    kwargs[key] || kwargs[:id] || subject_id_from_result(result)
  end

  private

  # Pull the first object of the configured subject_type out of a pool-style
  # success value, if present. Lets create services that return a fresh row
  # produce the right subject_id without bespoke overrides.
  def subject_id_from_result(result)
    return nil unless result.respond_to?(:success?) && result.success?

    value = result.value!
    return nil unless value.is_a?(Hash) && value[:objects].is_a?(Array)

    type = audit_subject_type
    value[:objects].find { |o| o[:objectType] == type }&.dig(:id)
  end

  # Prepended into the singleton class so `super` calls the original `.call`.
  # A service that raises (rather than returning a Failure) is *not*
  # audited — the exception propagates past us and we never reach the
  # record step. That's deliberate: a raised mutation is a bug, not a
  # user-attributable action, and wrapping every service in a transaction
  # to make audit-on-raise possible would require restructuring every
  # existing service. Failures returned via Result are audited normally.
  module Hook
    def call(*args, **kwargs)
      if Fiber[CASCADE_KEY]
        # Inner cascade: the outermost frame already owns the audit row.
        return super
      end

      Fiber[CASCADE_KEY] = true
      begin
        result = super
      ensure
        Fiber[CASCADE_KEY] = false
      end

      Auditable.record(service: self, kwargs: kwargs, result: result)
      result
    end
  end

  class << self
    # Per-request context (actor metadata, idempotency key, request id) set
    # by the route layer for the duration of a request. The wrapper merges
    # this into the audit row so service code doesn't have to thread it
    # through.
    REQUEST_CONTEXT_KEY = :auditable_request_context

    def with_request_context(context)
      previous = Fiber[REQUEST_CONTEXT_KEY]
      Fiber[REQUEST_CONTEXT_KEY] = context
      yield
    ensure
      Fiber[REQUEST_CONTEXT_KEY] = previous
    end

    def request_context
      Fiber[REQUEST_CONTEXT_KEY] || {}
    end

    def record(service:, kwargs:, result:)
      service_name = service.name
      outcome, error_code, error_message = classify(result)
      membership = kwargs[:membership]
      action_params = safe_audit_context(service, kwargs)
      subject_id = safe_subject_id(service, kwargs, result)
      ctx = request_context

      AuditLogEntry.create(
        service: service_name,
        outcome: outcome,
        actor_kind: ctx[:actor_kind] || (membership ? "user" : "system"),
        actor_user_id: ctx[:actor_user_id] || membership&.user_id,
        workspace_id: ctx[:workspace_id] || workspace_id_for(membership, kwargs),
        subject_type: service.audit_subject_type,
        subject_id: subject_id,
        error_code: error_code,
        error_message: error_message,
        action_params: action_params,
        idempotency_key_hash: ctx[:idempotency_key_hash],
        request_id: ctx[:request_id]
      )
    rescue StandardError => e
      # Audit must never break the underlying request. We log loudly so
      # missing rows don't go unnoticed in dev/CI, then swallow.
      APP_LOGGER.error do
        "[Auditable] Failed to record audit row for #{service.name}: #{e.class}: #{e.message}"
      end
    end

    private

    def classify(result)
      if result.success?
        ["success", nil, nil]
      else
        error = result.failure
        if error.respond_to?(:code) && error.code == :forbidden
          ["denied", error.code.to_s, error.message]
        elsif error.respond_to?(:code)
          ["error", error.code.to_s, error.message]
        else
          ["error", nil, error.to_s]
        end
      end
    end

    def safe_audit_context(service, kwargs)
      service.audit_context(**kwargs)
    rescue StandardError => e
      APP_LOGGER.warn { "[Auditable] audit_context raised for #{service.name}: #{e.class}: #{e.message}" }
      {}
    end

    def safe_subject_id(service, kwargs, result)
      service.audit_subject_id(result: result, **kwargs)
    rescue StandardError => e
      APP_LOGGER.warn { "[Auditable] audit_subject_id raised for #{service.name}: #{e.class}: #{e.message}" }
      nil
    end

    def workspace_id_for(membership, kwargs)
      kwargs[:workspace_id] || membership&.workspace_id
    end
  end
end
