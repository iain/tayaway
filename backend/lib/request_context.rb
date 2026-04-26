# frozen_string_literal: true

# Per-request ambient state — values that the route layer knows but
# downstream code (audit, logging, error reporting) doesn't, and which
# we don't want threaded through every internal signature. Modelled
# after ActiveSupport::CurrentAttributes: a fixed set of named accessors
# rather than a generic hash, so call sites can't typo a key into
# nothingness.
#
# Storage uses Fiber[] (not Thread.current[], which is also fiber-local
# but does not inherit into child fibers). The propagating semantics
# matter under Falcon: a child fiber spawned via Async {} during request
# handling inherits the same context, so the request_id stays consistent
# across logs even when work fans out.
#
# Each `with` call writes a new hash rather than mutating the stored
# one, so a child fiber that inherits the snapshot can't reach back and
# edit its parent's state.
module RequestContext
  KEYS = %i[idempotency_key_hash request_id].freeze
  STORAGE_KEY = :request_context
  private_constant :STORAGE_KEY

  class << self
    KEYS.each do |key|
      define_method(key) { Fiber[STORAGE_KEY]&.[](key) }
    end

    def with(**values)
      unknown = values.keys - KEYS
      raise ArgumentError, "Unknown RequestContext keys: #{unknown.join(", ")}" if unknown.any?

      previous = Fiber[STORAGE_KEY]
      Fiber[STORAGE_KEY] = (previous || {}).merge(values)
      yield
    ensure
      Fiber[STORAGE_KEY] = previous
    end

    # For tests only: clear the current fiber's context. Production code
    # should always go through `with` so the scope is delimited.
    def reset!
      Fiber[STORAGE_KEY] = nil
    end
  end
end
