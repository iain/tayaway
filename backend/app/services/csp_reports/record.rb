# frozen_string_literal: true

require "uri"

module CspReports
  # Ingests browser Content-Security-Policy violation reports (issue #315).
  #
  # The endpoint behind this is public and unauthenticated — browsers post
  # reports without cookies — so every value here is hostile input. Two
  # defences shape the code: nothing is stored verbatim (URLs collapse to an
  # origin or a path, free text is truncated), and the key space is bounded
  # (unknown directives are dropped, new distinct violations stop being
  # recorded past MAX_ROWS). Together with the per-IP throttle in RateLimiter
  # that keeps a spam run from turning the table into a write amplifier.
  #
  # Both report formats land here: the legacy `application/csp-report` body
  # (`{"csp-report": {...}}`, hyphenated keys) that `report-uri` sends, and
  # the Reporting API's `application/reports+json` batch (an array of
  # `{"type": "csp-violation", "body": {...}}`, camelCase keys) that
  # `report-to` sends. Browsers disagree on which they support, so the edge
  # advertises both and this normalises the two into one row shape.
  module Record
    # Generous for a batch of reports, small enough that a flood of oversized
    # bodies can't tie up a worker. Anything larger is dropped unparsed.
    MAX_BODY_BYTES = 16_384
    # A `report-to` batch can carry many entries; only the first few are worth
    # aggregating, and the rest would just be repeated writes for one request.
    MAX_REPORTS_PER_REQUEST = 10
    # Ceiling on *distinct* violations. Existing rows keep counting past this;
    # only new key combinations are refused, so a spam run can't grow the
    # table but also can't push real violations out.
    MAX_ROWS = 500

    # Browser extensions rewrite pages and trip the policy constantly — they
    # are the single largest source of false positives, and there is nothing
    # we could fix in response. Dropped before storage so the admin page shows
    # only violations we could actually act on.
    IGNORED_SCHEMES = %w[
      chrome-extension moz-extension safari-extension safari-web-extension
      webkit-masked-url chrome chromenull chromeinvoke chromeinvokeimmediate
    ].freeze

    # Reports whose blocked-uri is one of these carry no URL at all — they're
    # the CSP spec's placeholders — so they pass through unparsed.
    BLOCKED_URI_KEYWORDS = %w[inline eval wasm-eval trusted-types-policy trusted-types-sink self data blob filesystem].freeze

    # Real browsers only ever name a directive from this list. Anything else
    # is forged, and accepting it would let a caller mint unlimited distinct
    # rows.
    DIRECTIVES = %w[
      default-src script-src script-src-elem script-src-attr
      style-src style-src-elem style-src-attr img-src font-src connect-src
      media-src object-src child-src frame-src worker-src manifest-src
      prefetch-src form-action frame-ancestors base-uri navigate-to
      sandbox upgrade-insecure-requests block-all-mixed-content
      require-trusted-types-for trusted-types plugin-types
    ].freeze

    DISPOSITIONS = %w[enforce report].freeze

    # Every id in a client-side route is a UUID (see the frontend router), so
    # this is the whole of the app's path cardinality.
    UUID_SEGMENT = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/

    MAX_PATH_LENGTH = 200
    MAX_SAMPLE_TEXT_LENGTH = 200

    class << self
      # `body` is the raw request body; nothing upstream has parsed it, since
      # the report content types are not the JSON one Roda's parser handles.
      #
      # `disposition` is the endpoint's hint (see the route's ?d= param): the
      # policy that sent the browser here, used only when the report itself
      # doesn't say. It decides which bucket a violation lands in, nothing
      # more, so a forged one costs a mislabelled row and no more than that.
      def call(body:, user_agent: nil, disposition: nil, now: Time.now)
        Success()
          .bind { parse(body) }
          .bind { |payloads| Success(payloads.first(MAX_REPORTS_PER_REQUEST).filter_map { |p| normalize(p, user_agent, disposition) }) }
          .bind { |violations| Success(violations.count { |violation| store(violation, now) }) }
      end

      private

      def parse(body)
        raw = body.to_s
        if raw.bytesize > MAX_BODY_BYTES
          Failure(ServiceError.validation("Report too large"))
        else
          Success(payloads(JSON.parse(raw)))
        end
      rescue JSON::ParserError
        Failure(ServiceError.validation("Malformed report"))
      end

      # Unwraps either report format into a list of violation hashes. The
      # Reporting API multiplexes report types over one endpoint (deprecation,
      # intervention, …), so non-CSP entries are skipped rather than stored.
      def payloads(parsed)
        if parsed.is_a?(Hash) && parsed["csp-report"].is_a?(Hash)
          [parsed["csp-report"]]
        elsif parsed.is_a?(Array)
          parsed.select { |entry| entry.is_a?(Hash) && entry["type"] == "csp-violation" && entry["body"].is_a?(Hash) }
                .map { |entry| entry["body"].merge("user-agent" => entry["user_agent"]) }
        else
          []
        end
      end

      # nil for anything we won't store: an unknown directive, extension
      # noise, a report missing the fields that identify the violation.
      def normalize(payload, user_agent, hinted_disposition)
        raw_directive = field(payload, "effectiveDirective", "effective-directive", "violatedDirective", "violated-directive")
        directive = normalize_directive(raw_directive)
        blocked_uri = normalize_blocked_uri(field(payload, "blockedURL", "blocked-uri"))
        return nil if directive.nil? || blocked_uri.nil?

        {
          disposition: normalize_disposition(payload["disposition"], hinted_disposition),
          directive: directive,
          blocked_uri: blocked_uri,
          document_uri: normalize_document_uri(field(payload, "documentURL", "document-uri")),
          sample: sample(payload, user_agent)
        }
      end

      # Reads a field under any of its spellings — the Reporting API's
      # camelCase name or the legacy hyphenated one — in the order given.
      def field(payload, *names)
        names.filter_map { |name| payload[name] }.first
      end

      # `violated-directive` historically carried the whole source list
      # ("script-src 'self' https://…"); the directive name is the first token.
      def normalize_directive(raw)
        name = raw.to_s.strip.split(/\s+/).first.to_s.downcase
        name if DIRECTIVES.include?(name)
      end

      # The browser's own word first, the endpoint hint second, "enforce"
      # last — a report that says nothing at all is far more likely to have
      # come from the enforced policy than the Report-Only one.
      def normalize_disposition(raw, hinted)
        [raw.to_s, hinted.to_s].find { |value| DISPOSITIONS.include?(value) } || "enforce"
      end

      # Collapses to an origin, which is all the policy actually judged —
      # keeping the path would multiply rows per offending script and leak
      # whatever a hostile reporter cared to put in a query string.
      def normalize_blocked_uri(raw)
        value = raw.to_s.strip
        if value.empty?
          "unknown"
        elsif BLOCKED_URI_KEYWORDS.include?(value)
          value
        else
          origin(value)
        end
      end

      def origin(value)
        uri = URI.parse(value)
        scheme = uri.scheme&.downcase
        if IGNORED_SCHEMES.include?(scheme)
          nil
        elsif uri.host.nil?
          # A bare scheme ("about", "webkit-masked-url") or a relative
          # reference; both are already as coarse as an origin gets.
          scheme || "unknown"
        elsif uri.port && uri.port != uri.default_port
          "#{scheme}://#{uri.host.downcase}:#{uri.port}"
        else
          "#{scheme}://#{uri.host.downcase}"
        end
      rescue URI::InvalidURIError
        "unknown"
      end

      # Path only: the query string can carry invite tokens and other
      # personal data, and this table is read by an operator, not the user.
      # Record ids collapse to :id — a violation on a per-event page is one
      # bug, not one per event, and the aggregate has to key off the route
      # rather than the instance for that to hold.
      def normalize_document_uri(raw)
        uri = URI.parse(raw.to_s.strip)
        path = uri.path.to_s.gsub(UUID_SEGMENT, ":id")
        path.empty? ? "/" : truncate(path, MAX_PATH_LENGTH)
      rescue URI::InvalidURIError
        "unknown"
      end

      # Triage detail for the one violation we last saw. Overwritten on every
      # hit — an aggregate row keeps the latest example, not a history.
      def sample(payload, user_agent)
        {
          sourceFile: truncate(strip_query(field(payload, "sourceFile", "source-file")), MAX_PATH_LENGTH),
          lineNumber: integer(field(payload, "lineNumber", "line-number")),
          columnNumber: integer(field(payload, "columnNumber", "column-number")),
          statusCode: integer(field(payload, "statusCode", "status-code")),
          scriptSample: truncate(field(payload, "sample", "script-sample"), MAX_SAMPLE_TEXT_LENGTH),
          userAgent: truncate(payload["user-agent"] || user_agent, MAX_SAMPLE_TEXT_LENGTH)
        }.compact
      end

      def strip_query(value)
        value.to_s.split(/[?#]/).first
      end

      def integer(value)
        Integer(value.to_s, 10, exception: false)
      end

      def truncate(value, length)
        text = value.to_s
        if text.empty?
          nil
        elsif text.length > length
          "#{text[0, length]}…"
        else
          text
        end
      end

      # Bump-then-insert rather than an upsert: the row cap only applies to
      # violations we haven't seen, and checking it costs nothing on the hot
      # path (a repeat violation never counts rows). Returns the recorded
      # violation, or nil when the cap dropped it.
      def store(violation, now)
        key = violation.slice(:disposition, :directive, :blocked_uri, :document_uri)
        bumped = DB[:csp_reports].where(key).update(
          count: Sequel[:count] + 1,
          last_seen_at: now,
          sample: Sequel.pg_jsonb(violation[:sample])
        )
        if bumped.positive?
          key
        elsif DB[:csp_reports].count >= MAX_ROWS
          APP_LOGGER.warn { "[CspReports] Row cap reached; dropping new violation #{key[:directive]} #{key[:blocked_uri]}" }
          nil
        else
          insert(key, violation[:sample], now)
        end
      end

      # insert_conflict: two workers can race between the failed update and
      # this insert. Losing the race means the other worker recorded it, so
      # the report is not lost — just not counted twice.
      def insert(key, sample, now)
        APP_LOGGER.warn do
          "[CspReports] #{key[:disposition]} #{key[:directive]} blocked=#{key[:blocked_uri]} on #{key[:document_uri]}"
        end
        DB[:csp_reports]
          .insert_conflict(target: %i[disposition directive blocked_uri document_uri])
          .insert(key.merge(sample: Sequel.pg_jsonb(sample), first_seen_at: now, last_seen_at: now, count: 1))
        key
      end
    end
  end
end
