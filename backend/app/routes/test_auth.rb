# typed: false
# frozen_string_literal: true

# Test-only endpoint for creating authenticated sessions in e2e tests
# This endpoint should NOT be enabled in production
class App
  hash_path "/api/test/session" do |r|
    # Only allow in test/development/e2e environments
    unless %w[test development e2e].include?(ENV["RACK_ENV"])
      response.status = 404
      next { error: "Not found" }
    end

    r.post do
      result = Test::CreateSession.call(
        email: r.params["email"]&.strip&.downcase,
        name: r.params["name"]&.strip
      )
      handle_result(result)
    end
  end
end
