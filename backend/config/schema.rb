# frozen_string_literal: true

# Every env var the backend reads, declared in one place. The DSL is
# defined in `config/config.rb`; this file is data.

APP_CONFIG = Config.define do |c|
  c.optional :app_env, env: "RACK_ENV", type: :enum, values: Config::RACK_ENVS, default: "development",
             description: "Application environment"

  c.required :database_url, secret: true,
             description: "Postgres connection URL"
  c.required :app_secret, type: :base64, secret: true,
             description: "Session/cookie signing key (base64-encoded raw bytes)"
  c.required :frontend_url, production_only: true, type: :url, dev_default: "http://localhost:5173",
             description: "Public URL of the SPA — used in email links and WebAuthn config"

  c.optional :database_pool_size, type: :int, default: 16,
             description: "Sequel max_connections per worker"
  c.optional :web_concurrency, type: :int, default: 1,
             description: "Falcon web worker count"
  c.optional :job_concurrency, type: :int, default: 1,
             description: "Falcon jobs worker count"
  c.optional :falcon_url, type: :url, default: "http://localhost:9292",
             description: "Falcon bind URL"
  c.optional :static_dir,
             description: "Override for the frontend dist directory"
  c.optional :deleted_items_retention_days, type: :int, default: 7,
             description: "Soft-deleted item TTL (days)"
  c.optional :idempotency_key_ttl_hours, type: :int, default: 24,
             description: "Idempotency key TTL (hours)"
  c.optional :audit_log_retention_days, type: :int, default: 365,
             description: "Audit log retention (days)"
  c.optional :webauthn_extra_origins, type: :csv, default: [],
             description: "Extra WebAuthn origins (CSV)"
  c.optional :git_sha,
             description: "Build SHA — env, REVISION file, or git rev-parse"

  c.feature :push, requires: %i[vapid_public_key vapid_private_key],
            description: "Web push notifications" do |f|
    f.optional :vapid_public_key, description: "Web push public VAPID key"
    f.optional :vapid_private_key, secret: true, description: "Web push private VAPID key"
    f.optional :vapid_subject, default: "mailto:noreply@tayaway.nl",
               description: "RFC 8292 subject — contact for push providers"
  end

  c.feature :smtp, requires: %i[smtp_host smtp_username smtp_password],
            description: "Outbound email via SMTP" do |f|
    f.optional :smtp_host, description: "SMTP host"
    f.optional :smtp_port, type: :int, default: 587, description: "SMTP port"
    f.optional :smtp_username, description: "SMTP username"
    f.optional :smtp_password, secret: true, description: "SMTP password"
    f.optional :smtp_domain, default: "tayaway.nl", description: "SMTP HELO domain"
    f.optional :smtp_from_email, default: "noreply@tayaway.nl", description: "Default From address"
    f.optional :smtp_from_name, default: "Tayaway", description: "Default From display name"
    f.optional :smtp_reply_to_email, description: "Optional Reply-To address"
    f.optional :smtp_unsubscribe_email, description: "Optional List-Unsubscribe address"
  end
end
