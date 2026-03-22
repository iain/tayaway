# typed: false
# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  hash_path "/health" do |r|
    r.get do
      DB.test_connection
      { status: "healthy" }
    rescue Sequel::Error => e
      APP_LOGGER.error { "[Health] Database check failed: #{e.class} - #{e.message}" }
      response.status = 503
      { status: "unhealthy", reason: "database" }
    end
  end
end
