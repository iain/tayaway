# frozen_string_literal: true

# Renders a dotenv file from an APP_CONFIG schema. Both `.env.example` (via the
# `config:example` rake task) and the real per-env dotenvs (via
# `config/generate_dotenv.rb`) go through here, so config/schema.rb stays the
# single source of truth for which vars exist and the two outputs can't drift.
#
# `overrides` maps a spec key to a concrete value; those lines are emitted
# filled and uncommented — a required var with a value, or a generated secret.
# Every other var falls back to its dev_default/default, left commented unless
# it is required, which is how the schema documents optional overrides.
module DotenvTemplate
  class << self
    def render(config, overrides: {}, banner: [])
      lines = banner.dup
      config.entries.each do |spec|
        next if spec.key == :app_env

        lines.concat(spec_lines(spec, overrides))
        lines << ""
      end
      config.features.each do |feature|
        lines.concat(feature_header(config, feature))
        config.feature_entries.fetch(feature.name).each do |spec|
          lines.concat(spec_lines(spec, overrides))
          lines << ""
        end
      end
      lines.join("\n").chomp + "\n"
    end

    private

    def feature_header(config, feature)
      envs = feature.requires.map { |k| config.all_specs.find { _1.key == k }.env }
      [
        "# ── Feature: #{feature.description} ──",
        "# Enabled when all of #{envs.join(", ")} are set.",
        ""
      ]
    end

    def spec_lines(spec, overrides)
      lines = []
      lines << "# #{spec.description}" unless spec.description.to_s.empty?
      if overrides.key?(spec.key)
        lines << "#{spec.env}=#{overrides[spec.key]}"
      else
        lines << "# Generate with: ruby -e \"require 'securerandom'; puts SecureRandom.base64(32)\"" if spec.key == :app_secret
        prefix = required?(spec) ? "" : "# "
        lines << "#{prefix}#{spec.env}=#{default_value(spec)}"
      end
      lines
    end

    def required?(spec)
      spec.required == true || spec.required == :production_only
    end

    def default_value(spec)
      raw = spec.dev_default || spec.default
      case raw
      when nil then ""
      when Array then raw.join(",")
      else raw.to_s
      end
    end
  end
end
