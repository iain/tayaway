# frozen_string_literal: true

# Validates the new release's env file against the Config schema before
# Capistrano touches anything live. Runs ahead of database:migrate (both
# hook deploy:updated; this file loads first alphabetically and so runs
# first), so missing or malformed env vars abort the deploy while the
# old release is still serving — Falcon never gets restarted into a
# broken state.
#
# The `rake config:validate` task lives in backend/Rakefile; merely
# loading the Rakefile calls APP_CONFIG.load!, so a bad value raises
# immediately with every problem listed in a single error.
namespace :config do
  desc "Boot APP_CONFIG against the new release's env file before publishing"
  task :validate_release do
    on roles(:app) do
      within release_path.join("backend") do
        with rack_env: "production" do
          execute :bundle, "exec", "rake", "config:validate"
        end
      end
    end
  end
end

after "deploy:updated", "config:validate_release"
