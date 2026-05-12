# frozen_string_literal: true

require "base64"

# Single source of truth for every env var the backend reads.
#
# Boot order: `Config.load!` is the first thing `config/environment.rb` runs
# after `Dotenv.load`, so the rest of the boot can read `Config.x` without
# worrying about whether a var was set, valid, or coerced. Missing required
# vars in production raise here, before the app ever serves a request.
#
# Three states for a var:
#   - required: true            — must be set in every environment
#   - required: :production_only — must be set in production; uses dev_default elsewhere
#   - required: false (default)  — uses `default` (or `dev_default` outside production)
#
# Features group a set of vars under a single name. A feature is "enabled"
# when every var in its `requires:` list is present. A feature with *some*
# of its required vars set (but not all) is a configuration error, not a
# silent half-on state — almost always a typo or a half-applied secret roll.
#
# Tests use `Config.with(overrides) { ... }` for scoped overrides instead
# of mutating ENV in `before`/`after` hooks.
module Config
  Error = Class.new(StandardError)

  Spec = Data.define(:key, :env, :required, :type, :default, :dev_default, :secret, :values, :description)
  Feature = Data.define(:name, :requires, :description)

  RACK_ENVS = %w[production development test e2e].freeze

  class << self
    def spec(key, type: :string, env: nil, required: false, default: nil, dev_default: nil, secret: false, values: nil, description: "")
      Spec.new(
        key: key,
        env: env || key.to_s.upcase,
        required: required,
        type: type,
        default: default,
        dev_default: dev_default,
        secret: secret,
        values: values,
        description: description
      )
    end
  end

  ENTRIES = [
    spec(:app_env, env: "RACK_ENV", type: :enum, values: RACK_ENVS, default: "development",
         description: "Application environment"
    ),
    spec(:database_url, required: true, secret: true,
         description: "Postgres connection URL"
    ),
    spec(:app_secret, required: true, type: :base64, secret: true,
         description: "Session/cookie signing key (base64-encoded raw bytes)"
    ),
    spec(:frontend_url, required: :production_only, type: :url, dev_default: "http://localhost:5173",
         description: "Public URL of the SPA — used in email links and WebAuthn config"
    ),
    spec(:database_pool_size, type: :int, default: 16,
         description: "Sequel max_connections per worker"
    ),
    spec(:web_concurrency, type: :int, default: 1,
         description: "Falcon web worker count"
    ),
    spec(:job_concurrency, type: :int, default: 1,
         description: "Falcon jobs worker count"
    ),
    spec(:falcon_url, type: :url, default: "http://localhost:9292",
         description: "Falcon bind URL"
    ),
    spec(:static_dir, type: :string, default: nil,
         description: "Override for the frontend dist directory"
    ),
    spec(:deleted_items_retention_days, type: :int, default: 7,
         description: "Soft-deleted item TTL (days)"
    ),
    spec(:idempotency_key_ttl_hours, type: :int, default: 24,
         description: "Idempotency key TTL (hours)"
    ),
    spec(:audit_log_retention_days, type: :int, default: 365,
         description: "Audit log retention (days)"
    ),
    spec(:webauthn_extra_origins, type: :csv, default: [],
         description: "Extra WebAuthn origins (CSV)"
    ),
    spec(:git_sha, type: :string, default: nil,
         description: "Build SHA — env, REVISION file, or git rev-parse"
    )
  ].freeze

  FEATURES = [
    Feature.new(name: :push, requires: %i[vapid_public_key vapid_private_key],
                description: "Web push notifications"
    ),
    Feature.new(name: :smtp, requires: %i[smtp_host smtp_username smtp_password],
                description: "Outbound email via SMTP"
    )
  ].freeze

  FEATURE_ENTRIES = {
    push: [
      spec(:vapid_public_key, description: "Web push public VAPID key"),
      spec(:vapid_private_key, secret: true, description: "Web push private VAPID key"),
      spec(:vapid_subject, default: "mailto:noreply@tayaway.nl",
           description: "RFC 8292 subject — contact for push providers"
      )
    ].freeze,
    smtp: [
      spec(:smtp_host, description: "SMTP host"),
      spec(:smtp_port, type: :int, default: 587, description: "SMTP port"),
      spec(:smtp_username, description: "SMTP username"),
      spec(:smtp_password, secret: true, description: "SMTP password"),
      spec(:smtp_domain, default: "tayaway.nl", description: "SMTP HELO domain"),
      spec(:smtp_from_email, default: "noreply@tayaway.nl", description: "Default From address"),
      spec(:smtp_from_name, default: "Tayaway", description: "Default From display name"),
      spec(:smtp_reply_to_email, default: nil, description: "Optional Reply-To address"),
      spec(:smtp_unsubscribe_email, default: nil, description: "Optional List-Unsubscribe address")
    ].freeze
  }.freeze

  ALL_SPECS = (ENTRIES + FEATURE_ENTRIES.values.flatten).freeze
  SPECS_BY_KEY = ALL_SPECS.each_with_object({}) { |s, h| h[s.key] = s }.freeze

  ParseFailure = Data.define(:message)
  private_constant :ParseFailure

  class << self
    def load!(env: ENV)
      values, errors = build(env)
      raise Error, format_errors(errors) if errors.any?

      @values = values.freeze
      log_boot_summary
      @values
    end

    def feature_enabled?(name)
      feature = FEATURES.find { _1.name == name }
      return false unless feature

      feature.requires.all? { |k| present?(@values[k]) }
    end

    def to_h_redacted
      ALL_SPECS.each_with_object({}) do |s, h|
        next unless @values&.key?(s.key)

        h[s.key] = s.secret ? "[REDACTED]" : @values[s.key]
      end
    end

    def with(overrides)
      raise Error, "Config.with called before load!" unless @values

      snapshot = @values
      @values = @values.merge(overrides).freeze
      yield
    ensure
      @values = snapshot
    end

    RACK_ENVS.each { |name| define_method("#{name}?") { app_env == name } }
    def local? = !production?

    ALL_SPECS.each do |spec|
      define_method(spec.key) { @values&.fetch(spec.key, nil) }
    end

    private

    def values_snapshot = @values
    def restore_snapshot(snap) = (@values = snap)

    def build(env)
      values = {}
      errors = []

      # Resolve app_env first because other specs key off "required in
      # production" — we have to know which env we're in before deciding
      # whether a missing var is an error.
      app_env_value = parse_or_default(SPECS_BY_KEY[:app_env], env, errors, in_production: false)
      values[:app_env] = app_env_value
      in_production = app_env_value == "production"

      ENTRIES.each do |s|
        next if s.key == :app_env

        load_spec(s, env, values, errors, in_production: in_production)
      end

      FEATURES.each do |feature|
        present_keys = feature.requires.select { |k| present?(env[SPECS_BY_KEY[k].env]) }
        enabled = present_keys.length == feature.requires.length
        partial = !enabled && present_keys.any?

        # In production a half-configured feature is almost always a
        # typo or a half-applied secret roll — fail boot. In other envs
        # it's expected (dotenv scaffolding often has empty SMTP creds),
        # so the feature just stays disabled and the boot summary
        # surfaces it.
        if partial && in_production
          missing = feature.requires - present_keys
          errors << "Feature :#{feature.name} partially configured — missing #{missing.map { SPECS_BY_KEY[_1].env }.join(", ")}"
        end

        FEATURE_ENTRIES.fetch(feature.name).each do |s|
          must_be_set = enabled && feature.requires.include?(s.key)
          load_spec(s, env, values, errors, in_production: in_production, force_required: must_be_set)
        end
      end

      [values, errors]
    end

    def load_spec(spec, env, values, errors, in_production:, force_required: false)
      raw = env[spec.env]

      if present?(raw)
        parsed = parse_value(spec, raw)
        if parsed.is_a?(ParseFailure)
          errors << parsed.message
        else
          values[spec.key] = parsed
        end
        return
      end

      required_here =
        force_required ||
        spec.required == true ||
        (spec.required == :production_only && in_production)

      if required_here
        errors << "Required env var #{spec.env} is missing"
        return
      end

      values[spec.key] =
        if in_production || spec.dev_default.nil?
          spec.default
        else
          spec.dev_default
        end
    end

    def parse_or_default(spec, env, errors, in_production:)
      load_spec(spec, env, scratch = {}, errors, in_production: in_production)
      scratch[spec.key] || spec.default
    end

    def parse_value(spec, raw)
      case spec.type
      when :int
        Integer(raw)
      when :base64
        Base64.strict_decode64(raw)
      when :csv
        raw.split(",").map(&:strip).reject(&:empty?)
      when :enum
        # `spec` is a Data, not a Hash — `.values` is the enum allow-list.
        spec.values.include?(raw) ? raw : ParseFailure.new("#{spec.env}=#{raw.inspect} is not one of #{spec.values.join(", ")}") # rubocop:disable Performance/InefficientHashSearch
      else
        raw
      end
    rescue ArgumentError => e
      ParseFailure.new("#{spec.env}=#{raw.inspect} is invalid: #{e.message}")
    end

    def present?(value)
      !value.nil? && !value.to_s.empty?
    end

    def format_errors(errors)
      "Config validation failed:\n" + errors.map { "  - #{_1}" }.join("\n")
    end

    def log_boot_summary
      return unless defined?(APP_LOGGER) && APP_LOGGER

      enabled = FEATURES.map(&:name).select { |n| feature_enabled?(n) }
      disabled = FEATURES.map(&:name) - enabled
      APP_LOGGER.info do
        parts = ["[Config] env=#{app_env}"]
        parts << "features=[#{enabled.join(",")}]" if enabled.any?
        parts << "features_disabled=[#{disabled.join(",")}]" if disabled.any?
        parts.join(" ")
      end
    end
  end
end
