# frozen_string_literal: true

namespace :frontend do
  desc "Install frontend dependencies"
  task :install do
    on roles(:app) do
      within release_path do
        execute :pnpm, "install", "--frozen-lockfile"
      end
    end
  end

  desc "Build frontend for production"
  task :build do
    on roles(:app) do
      within release_path do
        execute :pnpm, "-C", "frontend", "exec", "vite", "build"
      end
    end
  end
end

after "bundler:install", "frontend:install"
after "frontend:install", "frontend:build"
