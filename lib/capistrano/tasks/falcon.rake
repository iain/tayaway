# frozen_string_literal: true

require "erb"
require "tempfile"

namespace :falcon do
  desc "Render and install the systemd unit file from the ERB template"
  task :install_unit do
    on roles(:app) do
      # Read the Ruby version from the remote server via mise.
      # RUBY_VERSION (e.g. "4.0.2") is used for the mise bin path.
      # RbConfig::CONFIG['ruby_version'] (e.g. "4.0.0") is the API/ABI version
      # used by RubyGems and Bundler for gem directory names — it stays on the
      # major.minor.0 series even as patch releases are installed.
      # Uses `cd` in the command so mise can find .mise.toml and resolve Ruby.
      mise = "/home/ubuntu/.local/bin/mise"
      rp = release_path
      ruby_version = capture("cd #{rp} && #{mise} exec -- ruby -e 'print RUBY_VERSION'").strip
      ruby_gem_version = capture("cd #{rp} && #{mise} exec -- ruby -e 'print RbConfig::CONFIG[\"ruby_version\"]'").strip

      template_path = File.expand_path("../../../config/deploy/tayaway-falcon.service.erb", __dir__)
      rendered = ERB.new(File.read(template_path)).result(binding)

      Tempfile.create("tayaway-falcon.service") do |f|
        f.write(rendered)
        f.flush
        upload! f.path, "/tmp/tayaway-falcon.service"
      end

      execute :sudo, "mv", "/tmp/tayaway-falcon.service", "/etc/systemd/system/tayaway-falcon.service"
      execute :sudo, "systemctl", "daemon-reload"
    end
  end

  desc "Gracefully reload Falcon via systemd, falling back to restart if not running"
  task :reload do
    on roles(:app) do
      if test("sudo systemctl is-active --quiet tayaway-falcon")
        execute :sudo, "systemctl", "reload", "tayaway-falcon"
      else
        execute :sudo, "systemctl", "restart", "tayaway-falcon"
      end
    end
  end

  desc "Restart Falcon via systemd (hard restart; drops in-flight connections)"
  task :restart do
    on roles(:app) do
      execute :sudo, "systemctl", "restart", "tayaway-falcon"
    end
  end

  desc "Start Falcon via systemd"
  task :start do
    on roles(:app) do
      execute :sudo, "systemctl", "start", "tayaway-falcon"
    end
  end

  desc "Stop Falcon via systemd"
  task :stop do
    on roles(:app) do
      execute :sudo, "systemctl", "stop", "tayaway-falcon"
    end
  end

  desc "Show Falcon status"
  task :status do
    on roles(:app) do
      execute :sudo, "systemctl", "status", "tayaway-falcon"
    end
  end
end

before "falcon:reload", "falcon:install_unit"
before "falcon:restart", "falcon:install_unit"
after "deploy:publishing", "falcon:restart"
