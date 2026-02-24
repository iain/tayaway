# frozen_string_literal: true

set :application, "tayaway"
set :repo_url, "file:///home/ubuntu/code/tayaway"
set :deploy_to, "/var/www/tayaway"
set :branch, "main"
set :keep_releases, 5

# Deploy to localhost — use Local backend instead of SSH.
# SSHKit's SSH backend wraps commands in POSIX ( export ...; cmd ) subshell
# syntax which is incompatible with the fish login shell.
set :sshkit_backend, SSHKit::Backend::Local

# Files and dirs shared across releases
set :linked_files, %w[backend/.env.production]
set :linked_dirs, %w[backend/vendor/bundle backend/log]

# Bundler — install gems from backend/Gemfile into shared/backend/vendor/bundle
set :bundle_gemfile, -> { release_path.join("backend", "Gemfile") }
set :bundle_path, -> { shared_path.join("backend", "vendor", "bundle") }
set :bundle_without, "development:test"
set :bundle_flags, "--quiet"

# mise integration — prefix commands so they run through mise exec.
# Bundle needs env -u BUNDLE_GEMFILE to avoid inheriting the Capistrano
# process's Gemfile when using the Local backend.
mise = "MISE_TRUSTED_CONFIG_PATHS=/var/www/tayaway /home/ubuntu/.local/bin/mise exec --"
SSHKit.config.command_map[:bundle] = "env -u BUNDLE_GEMFILE #{mise} bundle"
SSHKit.config.command_map[:ruby]   = "#{mise} ruby"
SSHKit.config.command_map[:rake]   = "#{mise} rake"
SSHKit.config.command_map[:node]   = "#{mise} node"
SSHKit.config.command_map[:pnpm]   = "#{mise} pnpm"
