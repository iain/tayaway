# typed: false
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

    # Dispatch to nested branches (events, etc.)
    r.hash_branches("api")
  end
end
