# frozen_string_literal: true

namespace :mise do
  desc "Verify the server's mise binary meets the min_version pinned in .mise.toml"
  task :check_version do
    # Parse min_version from the local .mise.toml — the same file that's
    # about to be deployed. If the server's mise is older, abort with a
    # clear message instead of failing later mid-deploy on an unrecognised
    # config key.
    toml = File.read(File.expand_path("../../../.mise.toml", __dir__))
    required = toml[/^min_version\s*=\s*"([^"]+)"/, 1]
    raise "Could not find min_version in .mise.toml" if required.nil?

    on roles(:app) do
      raw = capture(fetch(:mise_bin), "--version")
      actual = raw[/\d+\.\d+\.\d+/]
      raise "Could not parse mise version from: #{raw.inspect}" if actual.nil?

      if Gem::Version.new(actual) < Gem::Version.new(required)
        raise "mise #{actual} on the server is older than the required #{required} " \
              "(from .mise.toml min_version). Upgrade mise on the server before deploying."
      end
    end
  end

  desc "Install tool versions specified in .mise.toml"
  task :install do
    on roles(:app) do
      within release_path do
        execute fetch(:mise_bin), "install", "--yes"
      end
    end
  end
end

before "mise:install", "mise:check_version"
before "bundler:install", "mise:install"
