# typed: true
# frozen_string_literal: true

class App
  hash_path "/api/auth/magic-link" do |r|
    r.post do
      email = r.params["email"]&.strip&.downcase

      response.status = 400
      next { error: "Email is required" } if email.nil? || email.empty?

      user = User.first(Sequel.lit("LOWER(email) = ?", email))

      if user
        magic_token = MagicLinkToken.generate_for_user(user)
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        magic_link = magic_token.magic_link_url(frontend_url)

        puts "\n" + ("=" * 60)
        puts "MAGIC LINK FOR #{email}:"
        puts magic_link
        puts ("=" * 60) + "\n"
      else
        puts "No user found for email #{email}"
      end

      response.status = 200
      { message: "If an account exists with this email, a magic link has been sent." }
    end
  end

  hash_path "/api/auth/verify" do |r|
    r.post do
      token = r.params["token"]
      email = r.params["email"]&.strip&.downcase

      response.status = 400
      next { error: "Token and email are required" } if token.nil? || email.nil?

      magic_token = MagicLinkToken.find_valid_token(token, email)

      response.status = 401
      next { error: "Invalid or expired magic link" } unless magic_token

      magic_token.mark_used!
      session = Session.create_for_user(magic_token.user)

      response.status = 200
      {
        session_token: session.token,
        user: magic_token.user.to_api_hash
      }
    end
  end

  hash_path "/api/auth/logout" do |r|
    r.post do
      auth_header = r.headers["Authorization"]
      response.status = 401
      next { error: "Authorization required" } unless auth_header

      token = auth_header.sub(/^Bearer\s+/, "")
      session = Session.first(token: token)

      session&.destroy

      response.status = 200
      { message: "Logged out successfully" }
    end
  end

  hash_path "/api/auth/me" do |r|
    r.get do
      auth_header = r.headers["Authorization"]
      response.status = 401
      next { error: "Authorization required" } unless auth_header

      token = auth_header.sub(/^Bearer\s+/, "")
      session = Session.find_valid_session(token)

      response.status = 401
      next { error: "Invalid or expired session" } unless session

      response.status = 200
      { user: session.user.to_api_hash }
    end
  end
end
