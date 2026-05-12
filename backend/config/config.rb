# frozen_string_literal: true

require "base64"
require "uri"

# Per-app configuration object. The declarations live in
# `config/schema.rb`, which constructs the application's `APP_CONFIG`
# instance via this DSL:
#
#   APP_CONFIG = Config.define do |c|
#     c.required :database_url, secret: true
#     c.optional :web_concurrency, type: :int, default: 1
#     c.feature :push, requires: %i[vapid_public_key vapid_private_key] do |f|
#       f.optional :vapid_public_key
#       f.optional :vapid_private_key, secret: true
#     end
#   end
#
# Required-ness has three shapes:
#   - `required :x`                        — must be set in every environment
#   - `required :x, production_only: true` — must be set in production; uses `dev_default` elsewhere
#   - `optional :x, default: ...`          — never required
#
# A feature is "enabled" when every var in its `requires:` list is
# present. In production a half-configured feature fails boot. Outside
# production it stays off — dotenv scaffolding with empty SMTP creds is
# common and isn't a real error.
#
# Tests use `APP_CONFIG.with(overrides) { ... }` for scoped overrides
# instead of mutating ENV in before/after hooks.
class Config
  Error = Class.new(StandardError)

  Spec = Data.define(:key, :env, :required, :type, :default, :dev_default, :secret, :values, :description)
  Feature = Data.define(:name, :requires, :description)

  ParseFailure = Data.define(:message)
  private_constant :ParseFailure

  # Wrapper for `:url`-typed entries. Carries the URL as a string for
  # interpolation compatibility (`"#{url}"` and `url.to_s` both yield
  # the original string) and exposes ergonomic builders so call sites
  # don't have to interpolate paths by hand:
  #
  #   url.path("/events/#{id}")           # => "<base>/events/<id>"
  #   url.path("/invite", token: "abc")   # => "<base>/invite?token=abc"
  #   url.host                            # => "example.com"
  class Url
    attr_reader :base

    def initialize(base)
      @base = base.to_s.chomp("/")
      @uri = URI.parse(@base)
    end

    def to_s = @base
    def host = @uri.host

    def path(path, **query)
      path = "/#{path}" unless path.start_with?("/")
      query_string = query.empty? ? "" : "?#{URI.encode_www_form(query)}"
      "#{@base}#{path}#{query_string}"
    end

    def ==(other) = other.is_a?(Url) && @base == other.base
    alias_method :eql?, :==
    def hash = @base.hash
  end

  RACK_ENVS = %w[production development test e2e].freeze

  # DSL receiver. The top-level one (`TopBuilder`) also accepts
  # `feature`; the inner one used inside a feature block does not, so
  # features can't accidentally nest.
  class Builder
    attr_reader :entries

    def initialize
      @entries = []
    end

    def required(key, production_only: false, **opts)
      add(key, required: production_only ? :production_only : true, **opts)
    end

    def optional(key, **opts)
      add(key, required: false, **opts)
    end

    private

    def add(key, type: :string, env: nil, required: false, default: nil, dev_default: nil, secret: false, values: nil, description: "")
      @entries << Spec.new(
        key: key,
        env: env || key.to_s.upcase,
        required: required, type: type, default: default, dev_default: dev_default,
        secret: secret, values: values, description: description
      )
    end
  end

  class TopBuilder < Builder
    attr_reader :features, :feature_entries

    def initialize
      super
      @features = []
      @feature_entries = {}
    end

    def feature(name, requires:, description: "")
      @features << Feature.new(name: name, requires: requires, description: description)
      inner = Builder.new
      yield(inner)
      @feature_entries[name] = inner.entries.freeze
    end
  end

  def self.define
    builder = TopBuilder.new
    yield builder
    new(
      entries: builder.entries.freeze,
      features: builder.features.freeze,
      feature_entries: builder.feature_entries.freeze
    )
  end

  attr_reader :entries, :features, :feature_entries, :all_specs

  def initialize(entries:, features:, feature_entries:)
    @entries = entries
    @features = features
    @feature_entries = feature_entries
    @all_specs = (entries + feature_entries.values.flatten).freeze
    @specs_by_key = @all_specs.each_with_object({}) { |s, h| h[s.key] = s }.freeze
    @values = nil

    @all_specs.each do |spec|
      define_singleton_method(spec.key) { @values&.fetch(spec.key, nil) }
    end
  end

  def load!(env: ENV)
    values, errors = build(env)
    raise Error, format_errors(errors) if errors.any?

    @values = values.freeze
    log_boot_summary
    self
  end

  def feature_enabled?(name)
    feature = @features.find { _1.name == name }
    return false unless feature

    feature.requires.all? { |k| present?(@values[k]) }
  end

  def to_h_redacted
    @all_specs.each_with_object({}) do |s, h|
      next unless @values&.key?(s.key)

      h[s.key] = s.secret ? "[REDACTED]" : @values[s.key]
    end
  end

  def with(overrides)
    raise Error, "Config#with called before load!" unless @values

    coerced = overrides.to_h { |k, v| [k, coerce_override(k, v)] }
    snapshot = @values
    @values = @values.merge(coerced).freeze
    yield
  ensure
    @values = snapshot
  end

  RACK_ENVS.each { |name| define_method("#{name}?") { app_env == name } }
  def local? = !production?

  private

  def values_snapshot = @values
  def restore_snapshot(snap) = (@values = snap)

  def build(env)
    values = {}
    errors = []

    # Resolve app_env first — other specs key off "required in
    # production", so we need to know the env before deciding whether
    # a missing var is an error.
    app_env_spec = @specs_by_key[:app_env]
    app_env_value = parse_or_default(app_env_spec, env, errors, in_production: false)
    values[:app_env] = app_env_value
    in_production = app_env_value == "production"

    @entries.each do |s|
      next if s.key == :app_env

      load_spec(s, env, values, errors, in_production: in_production)
    end

    @features.each do |feature|
      present_keys = feature.requires.select { |k| present?(env[@specs_by_key[k].env]) }
      enabled = present_keys.length == feature.requires.length
      partial = !enabled && present_keys.any?

      # In production a half-configured feature is almost always a
      # typo or a half-applied secret roll — fail boot. In other envs
      # it's expected (dotenv scaffolding often has empty SMTP creds),
      # so the feature just stays disabled and the boot summary
      # surfaces it.
      if partial && in_production
        missing = feature.requires - present_keys
        errors << "Feature :#{feature.name} partially configured — missing #{missing.map { @specs_by_key[_1].env }.join(", ")}"
      end

      @feature_entries.fetch(feature.name).each do |s|
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

    fallback = in_production || spec.dev_default.nil? ? spec.default : spec.dev_default
    values[spec.key] = coerce_default(spec, fallback)
  end

  # Defaults from the schema are written as plain Ruby values
  # (`"http://localhost:5173"`, `16`, `[]`). Run them through the same
  # type wrapping as env-derived values so a caller never has to think
  # about whether a value originated from ENV or the default branch.
  def coerce_default(spec, value)
    coerce_for_type(spec.type, value)
  end

  # `with(...)` overrides come from test/app code as plain Ruby values
  # — apply the same type wrapping as load!.
  def coerce_override(key, value)
    spec = @specs_by_key[key]
    return value unless spec

    coerce_for_type(spec.type, value)
  end

  def coerce_for_type(type, value)
    return value if value.nil?

    case type
    when :url then value.is_a?(Url) ? value : Url.new(value)
    else value
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
    when :url
      Url.new(raw)
    when :enum
      # `spec` is a Data, not a Hash — `.values` is the enum allow-list.
      spec.values.include?(raw) ? raw : ParseFailure.new("#{spec.env}=#{raw.inspect} is not one of #{spec.values.join(", ")}") # rubocop:disable Performance/InefficientHashSearch
    else
      raw
    end
  rescue ArgumentError, URI::InvalidURIError => e
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

    enabled = @features.map(&:name).select { |n| feature_enabled?(n) }
    disabled = @features.map(&:name) - enabled
    APP_LOGGER.info do
      parts = ["[Config] env=#{app_env}"]
      parts << "features=[#{enabled.join(",")}]" if enabled.any?
      parts << "features_disabled=[#{disabled.join(",")}]" if disabled.any?
      parts.join(" ")
    end
  end
end

require_relative "schema"
