# typed: false
# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  hash_path "/api/auth/login-link" do |r|
    r.post do
      result = Auth::CreateLoginLink.call(email: r.params["email"]&.strip&.downcase)
      handle_result(result)
    end
  end

  hash_path "/api/auth/verify" do |r|
    r.post do
      result = Auth::VerifyToken.call(
        token: r.params["token"],
        ip: request.ip,
        user_agent: request.env["HTTP_USER_AGENT"]
      )
      if result.success?
        set_session_cookie(result.value![:session_token], Time.now + Session::EXPIRY_SECONDS)
      end
      handle_result(result)
    end
  end

  hash_path "/api/auth/logout" do |r|
    r.post do
      session = require_session

      DB[:sessions].where(id: session.id).delete
      clear_session_cookie
      response.status = 200
      { message: "Logged out successfully" }
    end
  end

  hash_path "/api/auth/ws-ticket" do |r|
    r.post do
      session = require_session

      result = Auth::CreateWsTicket.call(session_id: session.id)
      handle_result(result)
    end
  end

  hash_branch("api/auth", "passkeys") do |r|
    # Unauthenticated: passkey authentication
    r.on "authenticate" do
      r.hash_routes("api/auth/passkeys/authenticate")
    end

    # Authenticated: passkey management
    session = require_session

    user = User.find(session.user_id)
    unless user
      response.status = 401
      next { error: "Invalid or expired session" }
    end

    r.is do
      r.get do
        passkeys = PasskeyCredential.for_user(user.id)
        response.status = 200
        { passkeys: passkeys.map(&:to_api_hash) }
      end
    end

    r.on "register" do
      r.hash_routes("api/auth/passkeys/register")
    end

    r.on String do |passkey_id|
      r.is do
        r.put do
          result = Auth::Passkeys::Rename.call(
            user_id: user.id.to_s,
            passkey_id: passkey_id,
            name: r.params["name"]
          )
          handle_result(result)
        end

        r.delete do
          result = Auth::Passkeys::Delete.call(user_id: user.id.to_s, passkey_id: passkey_id)
          handle_result(result)
        end
      end
    end
  end

  hash_path "/api/auth/passkeys/register/begin" do |r|
    r.post do
      session = require_session
      result = Auth::Passkeys::BeginRegistration.call(user_id: session.user_id.to_s)
      handle_result(result)
    end
  end

  hash_path "/api/auth/passkeys/register/complete" do |r|
    r.post do
      session = require_session
      result = Auth::Passkeys::CompleteRegistration.call(
        user_id: session.user_id.to_s,
        challenge_token: r.params["challengeToken"],
        credential: r.params["credential"],
        name: r.params["name"]
      )
      handle_result(result)
    end
  end

  hash_path "/api/auth/passkeys/authenticate/begin" do |r|
    r.post do
      result = Auth::Passkeys::BeginAuthentication.call
      handle_result(result)
    end
  end

  hash_path "/api/auth/passkeys/authenticate/complete" do |r|
    r.post do
      result = Auth::Passkeys::CompleteAuthentication.call(
        challenge_token: r.params["challengeToken"],
        credential: r.params["credential"],
        ip: request.ip,
        user_agent: request.env["HTTP_USER_AGENT"]
      )
      if result.success?
        set_session_cookie(result.value![:session_token], Time.now + Session::EXPIRY_SECONDS)
      end
      handle_result(result)
    end
  end

  hash_branch("api", "auth") do |r|
    r.hash_routes("api/auth")
  end

  hash_branch("api/auth", "sessions") do |r|
    session = require_session

    user = User.find(session.user_id)
    unless user
      response.status = 401
      next { error: "Invalid or expired session" }
    end

    r.is do
      r.get do
        sessions = Session.for_user(user.id)
        response.status = 200
        {
          sessions: sessions.map do |s|
            s.to_api_hash.merge(current: s.id == session.id)
          end
        }
      end

      r.delete do
        result = Auth::RevokeOtherSessions.call(user_id: user.id, current_session_id: session.id)
        handle_result(result)
      end
    end

    r.on String do |session_id|
      r.is do
        r.delete do
          if session_id == session.id.to_s
            response.status = 400
            next { error: "Cannot delete current session. Use logout instead." }
          end

          result = Auth::DeleteSession.call(session_id: session_id, user_id: user.id)
          handle_result(result)
        end
      end
    end
  end

  hash_path "/api/auth/me" do |r|
    r.get do
      session = require_session

      user = User.find(session.user_id)
      unless user
        response.status = 401
        next { error: "Invalid or expired session" }
      end

      response.status = 200
      {
        user_id: user.id,
        email: user.email,
        name: user.name,
        phoneNumber: user.phone_number,
        birthday: user.birthday&.iso8601,
        locationName: user.location_name,
        latitude: user.location_coordinates&.[](1),
        longitude: user.location_coordinates&.[](0),
        iban: mask_iban(user.iban)
      }
    end
  end
end
