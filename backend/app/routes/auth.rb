# typed: true
# frozen_string_literal: true

class App
  hash_path "/api/auth/magic-link" do |r|
    r.post do
      result = Auth::CreateMagicLink.call(email: r.params["email"]&.strip&.downcase)
      handle_result(result)
    end
  end

  hash_path "/api/auth/verify" do |r|
    r.post do
      result = Auth::VerifyToken.call(
        token: r.params["token"],
        email: r.params["email"]&.strip&.downcase
      )
      handle_result(result)
    end
  end

  hash_path "/api/auth/logout" do |r|
    r.post do
      result = Auth::Logout.call(auth_header: r.headers["Authorization"])
      handle_result(result)
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

      user = session.user
      response.status = 200
      {
        user_id: user.id,
        email: user.email,
        name: user.name
      }
    end
  end
end
