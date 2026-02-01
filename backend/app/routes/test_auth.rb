# typed: true
# frozen_string_literal: true

# Test-only endpoint for creating authenticated sessions in e2e tests
# This endpoint should NOT be enabled in production
class App
  hash_path "/api/test/session" do |r|
    # Only allow in test/development environments
    unless ENV["RACK_ENV"] == "test" || ENV["RACK_ENV"] == "development"
      response.status = 404
      next { error: "Not found" }
    end

    r.post do
      email = r.params["email"]&.strip&.downcase
      name = r.params["name"]&.strip

      response.status = 400
      next { error: "Email is required" } if email.nil? || email.empty?

      # Find or create user
      user = User.first(Sequel.lit("LOWER(email) = ?", email))
      user ||= User.create(email: email, name: name)

      # Update name if provided and different
      if name && user.name != name
        user.update(name: name)
      end

      # Create session
      session = Session.create_for_user(user)

      response.status = 200
      {
        session_token: session.token,
        user: user.to_api_hash
      }
    end
  end
end
