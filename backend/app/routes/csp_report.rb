# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  # Where the edge's CSP `report-uri` / `report-to` point (containers/Caddyfile).
  #
  # A hash_path rather than a branch under "api" for the same reason /health
  # is one: this is infrastructure, not part of the versioned client API. It
  # sits outside the Idempotency wrapper, takes no session, and is exempt from
  # the protocol-version gate — a browser posting a violation report sends no
  # cookie, no CSRF header and no X-Client-Version, and a 426 would just turn
  # a violation into silence. See CspReports::Record for what gets stored.
  hash_path "/api/csp-report" do |r|
    r.post do
      # `r.GET` rather than `r.params`: params would merge in POST, and
      # Roda's json_parser reads (and under Rack 3 does not rewind) the body
      # to build it — leaving nothing for the read below. `d` says which
      # policy sent the browser here; the Report-Only candidate posts to
      # ?d=report so its violations don't read as blocked-in-production.
      disposition = r.GET["d"]
      # Read the body directly: the report content types (application/csp-report,
      # application/reports+json) are not what Roda's json_parser handles, and
      # the payload is a fixed browser-generated shape, not user params.
      result = CspReports::Record.call(
        body: r.body.read,
        user_agent: r.env["HTTP_USER_AGENT"],
        disposition: disposition
      )
      if result.success?
        response.status = 204
        nil
      else
        handle_result(result)
      end
    end
  end
end
