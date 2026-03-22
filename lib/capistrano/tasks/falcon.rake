# frozen_string_literal: true

namespace :falcon do
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

after "deploy:publishing", "falcon:reload"
