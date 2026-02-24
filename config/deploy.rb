# frozen_string_literal: true

set :application, "tayaway"
set :repo_url, "file:///home/ubuntu/code/tayaway"
set :deploy_to, "/var/www/tayaway"
set :branch, "main"
set :keep_releases, 5

# Files and dirs shared across releases
set :linked_files, %w[backend/.env.production]
set :linked_dirs, %w[backend/vendor/bundle backend/log]

# Bundler — install gems from backend/Gemfile into shared/backend/vendor/bundle
set :bundle_gemfile, -> { release_path.join("backend", "Gemfile") }
set :bundle_path, -> { shared_path.join("backend", "vendor", "bundle") }
set :bundle_without, "development:test"
set :bundle_flags, "--quiet"

# mise integration — prefix commands so they run through mise exec
SSHKit.config.command_map[:bundle] = "/home/ubuntu/.local/bin/mise exec -- bundle"
SSHKit.config.command_map[:ruby] = "/home/ubuntu/.local/bin/mise exec -- ruby"
SSHKit.config.command_map[:rake] = "/home/ubuntu/.local/bin/mise exec -- rake"
SSHKit.config.command_map[:node] = "/home/ubuntu/.local/bin/mise exec -- node"
SSHKit.config.command_map[:pnpm] = "/home/ubuntu/.local/bin/mise exec -- pnpm"

# Ensure mise is on PATH
set :default_env, {
  path: "/home/ubuntu/.local/bin:$PATH",
  mise_trusted_config_paths: "/var/www/tayaway"
}
