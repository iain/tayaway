# typed: true
# frozen_string_literal: true

class App
  hash_branch("api", "users") do |r|
    response.status = 401
    next { error: "Authorization required" } unless current_user

    # GET /api/users - List all users
    r.is do
      r.get do
        response.status = 200
        { users: User.order(:name, :email).all.map(&:to_api_hash) }
      end

      # POST /api/users - Create a new user
      r.post do
        name = r.params["name"]&.strip
        email = r.params["email"]&.strip&.downcase

        response.status = 400
        next { error: "Email is required" } if email.nil? || email.empty?

        if User.first(email: email)
          response.status = 400
          next { error: "A user with this email already exists" }
        end

        user = User.create(
          name: name&.empty? ? nil : name,
          email: email
        )

        response.status = 201
        { user: user.to_api_hash }
      end
    end
  end
end
