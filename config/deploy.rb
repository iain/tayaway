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
set :repo_url, "git@github.com:iain/tayaway-twee.git"
set :deploy_to, "/var/www/tayaway"
set :branch, "main"
set :keep_releases, 5

# Files and dirs shared across releases
set :linked_files, %w[backend/.env.production]
set :linked_dirs, %w[backend/vendor/bundle backend/log backend/.bundle]

# Bundler — install gems from backend/Gemfile into shared/backend/vendor/bundle
set :bundle_gemfile, -> { release_path.join("backend", "Gemfile") }
set :bundle_path, -> { shared_path.join("backend", "vendor", "bundle") }
set :bundle_without, "development:test"
set :bundle_flags, "--quiet"
set :bundle_version, 4

# mise integration — prefix commands so they run through mise exec
mise = "/home/ubuntu/.local/bin/mise exec --"
SSHKit.config.command_map[:bundle] = "#{mise} bundle"
SSHKit.config.command_map[:ruby]   = "#{mise} ruby"
SSHKit.config.command_map[:rake]   = "#{mise} rake"
SSHKit.config.command_map[:node]   = "#{mise} node"
SSHKit.config.command_map[:pnpm]   = "#{mise} pnpm"

# Ensure mise is on PATH and trusts the deploy directory
set :default_env, {
  path: "/home/ubuntu/.local/bin:$PATH",
  mise_trusted_config_paths: "/var/www/tayaway"
}
