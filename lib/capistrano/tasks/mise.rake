# frozen_string_literal: true

namespace :mise do
  desc "Install tool versions specified in .mise.toml"
  task :install do
    on roles(:app) do
      within release_path do
        execute "/home/tayaway/.local/bin/mise", "install", "--yes"
      end
    end
  end
end

before "bundler:install", "mise:install"
