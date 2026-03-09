#!/bin/bash
set -e

echo "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

echo "Installing backend dependencies..."
cd /workspace/backend
bundle config set --local path vendor/bundle
bundle install

echo "Installing frontend dependencies..."
cd /workspace/frontend
pnpm install

echo "Installing root dependencies (Playwright)..."
cd /workspace
pnpm install

echo "Installing Playwright browsers..."
pnpm exec playwright install --with-deps chromium

echo "Waiting for PostgreSQL..."
until pg_isready -h db -U tayaway -q; do
  sleep 1
done

echo "Configuring backend environment..."
cd /workspace/backend
secret=$(ruby -e "require 'securerandom'; puts SecureRandom.base64(32)")

# Write env files pointing to the 'db' container service.
# These are gitignored and will be overwritten on each container creation.
for env in development test e2e; do
  cat > ".env.${env}" <<ENVFILE
DATABASE_URL=postgres://tayaway:tayaway@db:5432/tayaway_${env}
PORT=9292
FRONTEND_URL=http://localhost:5173
APP_SECRET=${secret}
SMTP_HOST=localhost
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=noreply@tayaway.com
SMTP_DOMAIN=tayaway.com
ENVFILE
done

echo "Setting up databases..."
RACK_ENV=development bundle exec rake db:migrate
RACK_ENV=test bundle exec rake db:migrate
RACK_ENV=e2e bundle exec rake db:migrate

echo "Setup complete! Run 'mise run dev' to start the development server."
