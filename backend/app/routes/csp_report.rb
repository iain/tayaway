# typed: false
# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  # Unauthenticated — browsers send CSP violation reports without session cookies.
  hash_path "/api/csp-report" do |r|
    # Handles the legacy report-uri format only: Content-Type application/csp-report
    # with {"csp-report": {...}}. Does not handle the modern Reporting API format
    # (application/reports+json with [{"type": "csp-violation", "body": {...}}]).
    r.post do
      body = request.body.read
      parsed = JSON.parse(body)
      report = parsed["csp-report"] || {}

      blocked_uri = report["blocked-uri"].to_s

      # Filter browser extension noise — these are never legitimate app violations.
      if blocked_uri.start_with?("chrome-extension://", "moz-extension://")
        response.status = 204
        next
      end

      logged_blocked_uri = blocked_uri.empty? ? "<inline>" : blocked_uri

      APP_LOGGER.warn do
        "[CSP] Violation: blocked-uri=#{logged_blocked_uri.inspect} " \
          "violated-directive=#{report["violated-directive"].inspect} " \
          "document-uri=#{report["document-uri"].inspect} " \
          "source-file=#{report["source-file"].inspect} " \
          "line-number=#{report["line-number"].inspect}"
      end

      response.status = 204
      nil
    rescue JSON::ParserError
      response.status = 400
      { error: "Invalid report" }
    end
  end
end
