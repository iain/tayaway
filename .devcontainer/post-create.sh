#!/bin/bash
set -e

echo "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

# Mark onboarding complete so claude skips the interactive setup wizard
cat >/home/ubuntu/.claude.json <<'JSON'
{"hasCompletedOnboarding":true,"autoUpdates":false}
JSON

echo "Installing backend dependencies..."
cd /workspace/backend
bundle install

echo "Installing frontend dependencies..."
cd /workspace/frontend
aube install

echo "Installing root dependencies (Playwright)..."
cd /workspace
aube install

echo "Installing Playwright browsers..."
aube exec playwright install --with-deps chromium

echo "Waiting for PostgreSQL..."
for i in $(seq 1 30); do
  pg_isready -h db -U tayaway -q && break
  if [ "$i" -eq 30 ]; then
    echo "ERROR: PostgreSQL did not become ready in 30s" >&2
    exit 1
  fi
  sleep 1
done

echo "Configuring backend environment..."
cd /workspace/backend
secret=$(ruby -e "require 'securerandom'; puts SecureRandom.base64(32)")

# Write env files pointing to the 'db' container service.
# These are gitignored and will be overwritten on each container creation.
for env in development test e2e; do
  cat >".env.${env}" <<ENVFILE
DATABASE_URL=postgres://tayaway:tayaway@db:5432/tayaway_${env}
PORT=9292
FRONTEND_URL=http://localhost:5173
APP_SECRET=${secret}
SMTP_HOST=localhost
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=noreply@tayaway.nl
SMTP_DOMAIN=tayaway.nl
ENVFILE
done

echo "Setting up databases..."
MISE_ENV="development" mise exec -- bundle exec rake db:migrate
MISE_ENV="test" mise exec -- bundle exec rake db:migrate
MISE_ENV="e2e" mise exec -- bundle exec rake db:migrate

echo "Setup complete! Run 'mise run serve' to start the development server."
