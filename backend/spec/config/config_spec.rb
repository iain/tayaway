# frozen_string_literal: true

require "spec_helper"
require "base64"

RSpec.describe Config do
  # Exercise the live APP_CONFIG instance. Each example builds an env
  # hash, calls #load! against it, then asserts on the resulting state.
  # The around-block snapshots APP_CONFIG's values so each example is
  # isolated from the next and from the .env.test-loaded defaults.
  subject(:config) { APP_CONFIG }

  # A baseline env that satisfies every required-in-production var so each
  # example can express its scenario as a delta.
  let(:base_env) do
    {
      "RACK_ENV" => "development",
      "DATABASE_URL" => "postgres://example/db",
      "APP_SECRET" => Base64.strict_encode64("x" * 32),
      "FRONTEND_URL" => "http://localhost:5173"
    }
  end

  around do |example|
    snapshot = config.send(:values_snapshot)
    example.run
  ensure
    config.send(:restore_snapshot, snapshot)
  end

  describe "#load!" do
    it "decodes APP_SECRET from base64" do
      secret_bytes = "x" * 32
      config.load!(env: base_env.merge("APP_SECRET" => Base64.strict_encode64(secret_bytes)))
      expect(config.app_secret).to eq(secret_bytes)
    end

    it "applies the dev default for FRONTEND_URL outside production" do
      config.load!(env: base_env.tap { _1.delete("FRONTEND_URL") })
      expect(config.frontend_url).to eq("http://localhost:5173")
    end

    it "requires FRONTEND_URL in production" do
      env = base_env.merge("RACK_ENV" => "production").tap { _1.delete("FRONTEND_URL") }
      expect { config.load!(env: env) }
        .to raise_error(Config::Error, /FRONTEND_URL/)
    end

    it "fails fast when a required var is missing in production" do
      env = base_env.merge("RACK_ENV" => "production").tap { _1.delete("APP_SECRET") }
      expect { config.load!(env: env) }
        .to raise_error(Config::Error, /APP_SECRET/)
    end

    it "reports every missing required var in a single error" do
      env = base_env.merge("RACK_ENV" => "production")
      env.delete("APP_SECRET")
      env.delete("DATABASE_URL")
      expect { config.load!(env: env) }
        .to raise_error(Config::Error) { |e|
          expect(e.message).to include("APP_SECRET")
          expect(e.message).to include("DATABASE_URL")
        }
    end

    it "coerces int-typed vars" do
      config.load!(env: base_env.merge("DATABASE_POOL_SIZE" => "32"))
      expect(config.database_pool_size).to eq(32)
    end

    it "raises a clear error when an int-typed var is not numeric" do
      expect { config.load!(env: base_env.merge("DATABASE_POOL_SIZE" => "lots")) }
        .to raise_error(Config::Error, /DATABASE_POOL_SIZE/)
    end

    it "parses csv-typed vars into a stripped, non-empty list" do
      config.load!(env: base_env.merge("WEBAUTHN_EXTRA_ORIGINS" => "https://a.test, https://b.test, ,"))
      expect(config.webauthn_extra_origins).to eq(["https://a.test", "https://b.test"])
    end

    it "defaults csv-typed vars to an empty array" do
      config.load!(env: base_env)
      expect(config.webauthn_extra_origins).to eq([])
    end

    it "rejects RACK_ENV values not in the enum" do
      expect { config.load!(env: base_env.merge("RACK_ENV" => "staging")) }
        .to raise_error(Config::Error, /RACK_ENV/)
    end

    it "exposes app_env as a reader" do
      config.load!(env: base_env.merge("RACK_ENV" => "test"))
      expect(config.app_env).to eq("test")
    end
  end

  describe "feature detection" do
    it "is disabled when no feature-required vars are set" do
      config.load!(env: base_env)
      expect(config.feature_enabled?(:push)).to be(false)
      expect(config.feature_enabled?(:smtp)).to be(false)
    end

    it "enables :push when both VAPID keys are present" do
      config.load!(env: base_env.merge("VAPID_PUBLIC_KEY" => "pub", "VAPID_PRIVATE_KEY" => "priv"))
      expect(config.feature_enabled?(:push)).to be(true)
      expect(config.vapid_public_key).to eq("pub")
    end

    it "keeps :push disabled when only one VAPID key is set" do
      config.load!(env: base_env.merge("VAPID_PUBLIC_KEY" => "pub"))
      expect(config.feature_enabled?(:push)).to be(false)
    end

    it "enables :smtp when host/username/password are present" do
      config.load!(env: base_env.merge(
        "SMTP_HOST" => "smtp.example.com",
        "SMTP_USERNAME" => "u",
        "SMTP_PASSWORD" => "p"
      )
                  )
      expect(config.feature_enabled?(:smtp)).to be(true)
      expect(config.smtp_port).to eq(587)
    end

    it "raises in production when a feature is half-configured" do
      env = base_env.merge(
        "RACK_ENV" => "production",
        "SMTP_HOST" => "smtp.example.com",
        "SMTP_PASSWORD" => "p"
      )
      expect { config.load!(env: env) }
        .to raise_error(Config::Error, /SMTP_USERNAME/)
    end

    it "silently disables a half-configured feature outside production" do
      # Mirrors .env.test/.env.e2e, where SMTP_HOST is scaffolded with
      # empty credentials. The feature just stays off and gets reported
      # in the boot summary.
      config.load!(env: base_env.merge("SMTP_HOST" => "smtp.example.com"))
      expect(config.feature_enabled?(:smtp)).to be(false)
    end

    it "applies feature-scoped defaults regardless of activation state" do
      config.load!(env: base_env)
      expect(config.vapid_subject).to eq("mailto:noreply@tayaway.nl")
    end
  end

  describe "#to_h_redacted" do
    it "redacts secret-tagged values" do
      config.load!(env: base_env)
      redacted = config.to_h_redacted
      expect(redacted[:app_secret]).to eq("[REDACTED]")
      expect(redacted[:database_url]).to eq("[REDACTED]")
      expect(redacted[:frontend_url]).to eq("http://localhost:5173")
    end
  end

  describe "#with" do
    before { config.load!(env: base_env) }

    it "scopes overrides to the block and restores afterwards" do
      original = config.frontend_url
      config.with(frontend_url: "https://override.test") do
        expect(config.frontend_url).to eq("https://override.test")
      end
      expect(config.frontend_url).to eq(original)
    end

    it "restores values even when the block raises" do
      original = config.frontend_url
      expect {
        config.with(frontend_url: "https://x.test") { raise "boom" }
      }.to raise_error("boom")
      expect(config.frontend_url).to eq(original)
    end

    it "temporarily activates a feature when its required keys are provided" do
      expect(config.feature_enabled?(:push)).to be(false)
      config.with(vapid_public_key: "pub", vapid_private_key: "priv") do
        expect(config.feature_enabled?(:push)).to be(true)
      end
      expect(config.feature_enabled?(:push)).to be(false)
    end
  end

  describe "env predicates" do
    it "exposes production?/development?/test?/e2e? matching app_env" do
      config.load!(env: base_env.merge("RACK_ENV" => "test"))
      expect(config.test?).to be(true)
      expect(config.production?).to be(false)
      expect(config.development?).to be(false)
      expect(config.e2e?).to be(false)
    end
  end
end
