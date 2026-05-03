# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

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
            latitude: ValidationLimits.parse_coordinate(r.params["latitude"]),
            longitude: ValidationLimits.parse_coordinate(r.params["longitude"]),
            iban: r.params["iban"],
            iban_holder_name: r.params["ibanHolderName"]
          )
          handle_result(result)
        end
      end
    end
  end
end
