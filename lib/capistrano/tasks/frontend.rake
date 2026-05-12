# frozen_string_literal: true

namespace :frontend do
  desc "Install frontend dependencies"
  task :install do
    on roles(:app) do
      within release_path do
        # Direct invocation rather than `mise run //frontend:setup:deps`
        # because that task is a bare `pnpm install` (for dev ergonomics);
        # deploys want --frozen-lockfile so a divergent lockfile fails the
        # build instead of silently regenerating it.
        execute :pnpm, "install", "--frozen-lockfile"
      end
    end
  end

  desc "Build frontend for production"
  task :build do
    on roles(:app) do
      within release_path do
        execute :mise, "run", "//frontend:build"
      end
    end
  end
end

after "bundler:install", "frontend:install"
after "frontend:install", "frontend:build"
