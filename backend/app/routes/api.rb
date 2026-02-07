# typed: false
# frozen_string_literal: true

class App
  hash_branch "api" do |r|
    r.on "health" do
      r.get do
        { status: "healthy" }
      end
    end

    # Dispatch to nested branches (events, etc.)
    r.hash_branches("api")
  end
end
