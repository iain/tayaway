# frozen_string_literal: true

namespace :database do
  desc "Run database migrations"
  task :migrate do
    on roles(:db) do
      within release_path.join("backend") do
        with rack_env: "production" do
          execute :bundle, "exec", "rake", "db:migrate"
        end
      end
    end
  end
end

after "deploy:updated", "database:migrate"
