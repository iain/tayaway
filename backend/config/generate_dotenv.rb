# frozen_string_literal: true

# Generates a filled backend/.env.<env> from config/schema.rb so a fresh clone
# gets a working config without hand-editing. It reads only the schema (no
# APP_CONFIG.load!), so it runs before any env vars exist — which is the whole
# point of the bootstrap path.
#
# Secrets are generated locally; the files are gitignored. Production secrets
# come only from the sops-encrypted .env.production.yaml, never from here.
#
# Usage: bundle exec ruby config/generate_dotenv.rb <development|test|e2e>
# An existing target file is left untouched.

require "securerandom"
require "web_push"
require_relative "../lib/config"
require_relative "../lib/dotenv_template"

# Per-env values that differ from the schema's dev-oriented defaults: each env
# owns its database, and the e2e frontend serves on its own port.
ENV_DATABASES = {
  "development" => "tayaway_development",
  "test" => "tayaway_test",
  "e2e" => "tayaway_e2e"
}.freeze
ENV_FRONTEND_URLS = { "e2e" => "http://localhost:5174" }.freeze

target = ARGV[0]
unless ENV_DATABASES.key?(target)
  warn "usage: generate_dotenv.rb <#{ENV_DATABASES.keys.join("|")}>"
  exit 1
end

path = ".env.#{target}"
if File.exist?(path)
  puts "#{path} already exists — leaving it"
  exit 0
end

# Fill the required-but-defaultless vars: a per-env DATABASE_URL, a signing
# secret, and a web-push VAPID keypair (generated as a matched pair). Anything
# else keeps its schema default.
vapid = WebPush.generate_key
overrides = {
  database_url: "postgres://tayaway@localhost:5432/#{ENV_DATABASES.fetch(target)}",
  app_secret: SecureRandom.base64(32),
  vapid_public_key: vapid.public_key,
  vapid_private_key: vapid.private_key
}
frontend_url = ENV_FRONTEND_URLS[target]
overrides[:frontend_url] = frontend_url if frontend_url

banner = [
  "# Generated for the #{target} env by `mise run setup:env` from config/schema.rb.",
  "# Gitignored — safe to delete and regenerate. Secrets here are local",
  "# throwaways; production secrets live in the sops-encrypted .env.production.yaml.",
  ""
]

File.write(path, DotenvTemplate.render(APP_CONFIG, overrides: overrides, banner: banner))
puts "Generated backend/#{path}"
