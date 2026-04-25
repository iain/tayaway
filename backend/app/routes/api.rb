# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  hash_branch "api" do |r|
    r.on "health" do
      r.get do
        { status: "healthy" }
      end
    end

    # Wrap dispatch so every mutating route is covered by Idempotency without
    # per-route opt-in. See Idempotency for the contract.
    begin
      Idempotency.wrap(request: r, response: response, user: current_user) do
        r.hash_branches("api")
      end
    rescue Idempotency::ConflictError
      response.status = 409
      { error: "Request with this idempotency key is still in flight" }
    end
  end
end
