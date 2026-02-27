# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "users") do |r|
    # Unauthenticated routes
    r.on "email-change" do
      # POST /api/users/email-change/verify - Verify email change (no auth — token is proof)
      r.on "verify" do
        r.post do
          result = Users::VerifyEmailChange.call(token: r.params["token"])
          handle_result(result)
        end
      end

      # POST /api/users/email-change/request - Request email change (requires auth)
      r.on "request" do
        r.post do
          user = require_auth
          result = Users::RequestEmailChange.call(
            user_id: user.id,
            new_email: r.params["email"]&.strip
          )
          handle_result(result)
        end
      end
    end

    user = require_auth

    # /api/users/:id routes
    r.on String do |id|
      r.is do
        # PUT /api/users/:id - Update user profile (personal settings)
        r.put do
          result = Users::UpdateProfile.call(
            user_id: id,
            current_user_id: user.id,
            name: r.params["name"]&.strip,
            phone_number: r.params["phoneNumber"],
            birthday: r.params["birthday"],
            location_name: r.params["locationName"],
            latitude: r.params["latitude"]&.to_f,
            longitude: r.params["longitude"]&.to_f,
            iban: r.params["iban"]
          )
          handle_result(result)
        end
      end
    end
  end
end
