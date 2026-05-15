# frozen_string_literal: true

require "shellwords"

# SSHKit wraps commands with environment variables in POSIX ( export ...; cmd )
# subshell syntax, which is incompatible with the fish login shell. This patch
# wraps all SSH commands in /bin/bash -c so they execute correctly regardless
# of the remote user's shell.
module BashCommandWrapper
  def execute_command(cmd)
    original = cmd.to_command
    wrapped = "/bin/bash -c #{Shellwords.shellescape(original)}"
    cmd.define_singleton_method(:to_command) { wrapped }
    super(cmd)
  end
end

SSHKit::Backend::Netssh.prepend(BashCommandWrapper)

set :application, "tayaway"
set :repo_url, "git@github.com:iain/tayaway.git"
set :deploy_to, "/var/www/tayaway"
set :branch, ENV.fetch("BRANCH", "main")
set :keep_releases, 5

# Files and dirs shared across releases
set :linked_files, %w[backend/.env.production]
set :linked_dirs, %w[backend/vendor/bundle backend/log backend/.bundle backend/data]

# Bundler — install gems from backend/Gemfile into shared/backend/vendor/bundle
set :bundle_gemfile, -> { release_path.join("backend", "Gemfile") }
set :bundle_path, -> { shared_path.join("backend", "vendor", "bundle") }
set :bundle_without, "development:test"
set :bundle_flags, "--quiet"
set :bundle_version, 4

# mise integration — prefix commands so they run through mise exec.
# Production runs as the restricted `tayaway` system user; mise lives
# in that user's home dir.
set :mise_bin, "/home/tayaway/.local/bin/mise"
mise_bin = fetch(:mise_bin)
mise_dir = File.dirname(mise_bin)
mise_exec = "#{mise_bin} exec --"
SSHKit.config.command_map[:mise]   = mise_bin
SSHKit.config.command_map[:bundle] = "#{mise_exec} bundle"
SSHKit.config.command_map[:ruby]   = "#{mise_exec} ruby"
SSHKit.config.command_map[:rake]   = "#{mise_exec} rake"
SSHKit.config.command_map[:node]   = "#{mise_exec} node"
SSHKit.config.command_map[:pnpm]   = "#{mise_exec} pnpm"

# Ensure mise is on PATH, trusts the deploy directory, and has the
# experimental flag turned on (monorepo mode is gated behind it in the
# 2026.5.x line — without it, mise ignores backend/frontend mise.toml).
set :default_env, {
  path: "#{mise_dir}:$PATH",
  mise_trusted_config_paths: "/var/www/tayaway",
  mise_experimental: "1",
  # The root [hooks] postinstall fans out to setup:deps-root, which is dev
  # ergonomics (Capistrano gems, Playwright browsers, prettier). Capistrano
  # handles backend and frontend dependency installation explicitly, so the
  # hook would only waste time and pull non-production tooling onto the box.
  mise_hooks: "0"
}
