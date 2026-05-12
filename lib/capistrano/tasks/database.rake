# frozen_string_literal: true

# IMPORTANT: Migrations run BEFORE the app restarts (deploy:updated hook).
# This means old code is still serving traffic when migrations execute.
# All migrations MUST be additive (add columns, tables, indexes).
#
# Destructive changes (dropping columns, adding NOT NULL, renaming) must be
# split across two deploys:
#   1. Deploy: stop using the column/table in code
#   2. Deploy: remove the column/table in a migration
namespace :database do
  desc "Run database migrations"
  task :migrate do
    on roles(:db) do
      within release_path.join("backend") do
        with mise_env: "production" do
          execute :bundle, "exec", "rake", "db:migrate"
        end
      end
    end
  end
end

after "deploy:updated", "database:migrate"
