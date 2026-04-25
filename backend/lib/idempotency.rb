# frozen_string_literal: true

# Stripe-style server-side idempotency for mutating API requests.
#
# A client that retries the same mutation (because the original response was
# never received) sends the same `Idempotency-Key` header. The first request
# runs the work and caches its response inside the same DB transaction; any
# retry replays the cached response without re-running the work.
#
# Replays are scoped to (user_id, key) so different users can't collide.
# A retry that arrives with a different request body for the same key is a
# client bug and is rejected with 422 rather than silently replayed.
#
# The replay path serves the cached body verbatim with `Content-Type:
# application/json`; response headers other than the status code are not
# preserved. None of the current mutating routes rely on extra headers (e.g.
# `Location:` on 201 Created), so this is fine — but a future route that does
# would need to either store its headers in the cache row or opt out.
#
# Side effects performed by the route block (emails, third-party calls) are
# *not* part of the DB transaction, so a concurrent retry that loses the
# insert race will have already fired those side effects before its mutation
# rolls back. For routes whose only side effect is the DB write itself this
# is correct; routes with external side effects need their own dedupe.
module Idempotency
  HEADER = "HTTP_IDEMPOTENCY_KEY"
  MUTATING_METHODS = %w[POST PUT PATCH DELETE].freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  # Raised when a concurrent retry won the cache-insert race but its row is
  # not (yet) visible to us. Caller should map to 409.
  ConflictError = Class.new(StandardError)

  module_function

  # Wrap a Roda route block with idempotency handling. For an authenticated
  # mutating request that carries a valid Idempotency-Key header, route
  # execution and the cache-row insert run inside one DB transaction so the
  # mutation and its cached response always commit or roll back together.
  # For any other request the block runs untouched.
  #
  # The block is expected to halt the request via Roda's `:halt` throw (the
  # normal behaviour for a matched route). We catch that throw to capture the
  # rack response, write the cache row in the same transaction, and re-throw
  # `:halt` once the transaction commits. A raised exception inside the block
  # rolls back both the mutation and the cache write.
  def wrap(request:, user:, &block)
    return yield unless applies?(request, user)

    key = request.env[HEADER].to_s.strip
    fingerprint = fingerprint_for(request)

    if (cached = lookup(user.id, key))
      return replay(cached, fingerprint)
    end

    captured = nil
    lost_race = false

    DB.transaction do
      captured = catch(:halt) do
        yield
        nil
      end
      next unless captured

      status, _headers, body_parts = captured
      body_str = serialise_body(body_parts)

      # ON CONFLICT DO NOTHING avoids raising inside the transaction (a
      # raised UniqueConstraintViolation would poison the open transaction
      # and force us to rescue across the txn boundary). On a conflict the
      # insert returns nil — we then roll back our own mutation and replay
      # the row that the winning concurrent request committed.
      inserted = DB[:idempotency_keys].insert_conflict.insert(
        user_id: user.id,
        idempotency_key: key,
        request_fingerprint: fingerprint,
        response_status: status,
        response_body: body_str,
        created_at: Time.now
      )

      if inserted.nil?
        lost_race = true
        captured = nil
        raise Sequel::Rollback
      end
    end

    if lost_race
      cached = lookup(user.id, key)
      unless cached
        APP_LOGGER.warn { "[Idempotency] In-flight conflict for user=#{user.id} key=#{key}" }
        raise ConflictError, "Idempotency key in flight"
      end
      if cached[:request_fingerprint] != fingerprint
        # The race is itself surprising; combined with a body mismatch it
        # almost certainly means a buggy client is reusing the same key for
        # different requests in parallel. Worth a log so the 422 isn't silent.
        APP_LOGGER.warn { "[Idempotency] Lost-race fingerprint mismatch for user=#{user.id} key=#{key}" }
      end
      return replay(cached, fingerprint)
    end

    throw :halt, captured if captured
  end

  def applies?(request, user)
    return false unless user
    return false unless MUTATING_METHODS.include?(request.request_method)

    raw = request.env[HEADER]
    !raw.nil? && !raw.to_s.strip.empty?
  end

  def lookup(user_id, key)
    DB[:idempotency_keys].where(user_id: user_id, idempotency_key: key).first
  end

  def replay(cached, fingerprint)
    if cached[:request_fingerprint] != fingerprint
      throw :halt, [422, JSON_HEADERS.dup, [JSON.dump({ error: "Idempotency key reused with a different request" })]]
    end

    throw :halt, [cached[:response_status], JSON_HEADERS.dup, [cached[:response_body]]]
  end

  # Fingerprint = SHA256(method | path | canonicalised params).
  # We hash parsed params (not the raw body) because Roda's json_parser has
  # already consumed the input. Sorting hash keys keeps the digest stable
  # across different JSON serialisations of the same payload. Query-string
  # params are included intentionally — they are part of the request and
  # several mutating routes use them (e.g. POST /api/expenses?event_id=…).
  def fingerprint_for(request)
    payload = "#{request.request_method}|#{request.path_info}|#{JSON.dump(canonical(request.params))}"
    Digest::SHA256.hexdigest(payload)
  end

  def canonical(value)
    case value
    when Hash then value.keys.sort.each_with_object({}) { |k, h| h[k] = canonical(value[k]) }
    when Array then value.map { |v| canonical(v) }
    else value
    end
  end

  # Rack bodies are an Enumerable of strings (often an Array, sometimes a
  # BodyProxy or a streamed body). Reading via `each` works for all of them
  # and lets us call `close` afterwards so any cleanup callbacks the body
  # registered (e.g. connection release) actually fire. Non-Enumerable bodies
  # would silently coerce to a useless `inspect` string via `to_s`, so we
  # reject them explicitly.
  def serialise_body(body_parts)
    raise ArgumentError, "Unsupported rack body shape: #{body_parts.class}" unless body_parts.respond_to?(:each)

    parts = []
    body_parts.each { |chunk| parts << chunk }
    body_parts.close if body_parts.respond_to?(:close)
    parts.join
  end
end
