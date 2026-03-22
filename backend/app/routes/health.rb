# typed: false
# frozen_string_literal: true

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
