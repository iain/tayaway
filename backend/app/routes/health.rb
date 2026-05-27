# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  # `version` (APP_CONFIG.git_sha) is exposed on this public, unauthenticated
  # endpoint deliberately: it makes the live build obvious and lets deploy.sh
  # assert the right version is serving. Safe because the repo is private — the
  # commit SHA is an opaque token to an outsider, mapping to no fetchable source
  # or CVE list. If the repo ever goes public, gate this behind auth or report a
  # coarse release tag instead of the exact SHA.
  hash_path "/health" do |r|
    r.get do
      DB.test_connection
      { status: "healthy", version: APP_CONFIG.git_sha }
    rescue Sequel::Error => e
      APP_LOGGER.error { "[Health] Database check failed: #{e.class} - #{e.message}" }
      response.status = 503
      { status: "unhealthy", reason: "database" }
    end
  end
end
