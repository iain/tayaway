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
module Idempotency
  HEADER = "HTTP_IDEMPOTENCY_KEY"
  MAX_KEY_LENGTH = 255
  MUTATING_METHODS = %w[POST PUT PATCH DELETE].freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  ConflictError = Class.new(StandardError)

  module_function

  # Wrap a Roda route block. For an authenticated mutating request that carries
  # a valid Idempotency-Key header, route execution and the cache write happen
  # in a single DB transaction; for any other request the block runs untouched.
  #
  # The block is expected to halt the request (Roda's normal behaviour for
  # matched routes), so we catch `:halt` to capture the rack response, write
  # the cache row inside the same transaction, and re-throw `:halt` once the
  # transaction commits. A halt that escapes commits the cache row; a raised
  # exception rolls it back along with the mutation — the response and the
  # cache always agree.
  def wrap(request:, response:, user:, &block)
    return yield unless applies?(request, user)

    key = request.env[HEADER].to_s.strip
    fingerprint = fingerprint_for(request)

    if (cached = lookup(user.id, key))
      replay(cached, fingerprint)
    end

    captured = nil
    begin
      DB.transaction do
        captured = catch(:halt) do
          yield
          nil
        end
        next unless captured

        status, _headers, body_parts = captured
        body_str = body_parts.is_a?(Array) ? body_parts.join : body_parts.to_s
        DB[:idempotency_keys].insert(
          user_id: user.id,
          idempotency_key: key,
          request_fingerprint: fingerprint,
          response_status: status,
          response_body: body_str,
          created_at: Time.now
        )
      end
    rescue Sequel::UniqueConstraintViolation
      # A concurrent retry inserted the row first; replay its cached response.
      cached = lookup(user.id, key)
      raise ConflictError, "Idempotency key in flight" unless cached

      replay(cached, fingerprint)
    end

    throw :halt, captured if captured
  end

  def applies?(request, user)
    return false unless user
    return false unless MUTATING_METHODS.include?(request.request_method)

    raw = request.env[HEADER]
    !raw.nil? && !raw.to_s.strip.empty? && raw.to_s.length <= MAX_KEY_LENGTH
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
  # We hash the parsed params (not the raw body) because Roda's json_parser
  # has already consumed the input; sorting keys keeps the hash stable across
  # different JSON serialisations of the same payload.
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
end
