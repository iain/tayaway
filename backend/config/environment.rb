# frozen_string_literal: true

VALID_ENVIRONMENTS = %w[production development test e2e].freeze
boot_env = ENV.fetch("RACK_ENV", "development")
unless VALID_ENVIRONMENTS.include?(boot_env)
  raise "Invalid RACK_ENV=#{boot_env.inspect}. Must be one of: #{VALID_ENVIRONMENTS.join(", ")}"
end
APP_DIR = Pathname(File.expand_path("..", __dir__))

require "bundler/setup"
Bundler.require(:default, boot_env)

# Make the Result monad constructors (Success, Failure) available everywhere
# without each model/service/policy having to repeat `include Dry::Monads[:result]`.
Object.include Dry::Monads[:result]

Dotenv.load("#{APP_DIR}/.env.#{boot_env}") unless boot_env == "production"

# GIT_SHA can come from three places in priority order — env, the REVISION
# file written by Capistrano, or `git rev-parse` on a working tree. Resolve
# the fallback chain *before* APP_CONFIG.load! so Config sees a single source.
ENV["GIT_SHA"] ||=
  (File.read("#{APP_DIR}/REVISION").strip[0, 7] if File.exist?("#{APP_DIR}/REVISION")) ||
  `git rev-parse --short HEAD 2>/dev/null`.strip

require_relative "../lib/config"
APP_CONFIG.load!

require "logger"
APP_LOGGER = Logger.new($stdout)
APP_LOGGER.level = case APP_CONFIG.app_env
                   when "production" then Logger::INFO
                   when "test" then Logger::FATAL
                   when "e2e" then Logger::WARN
                   else Logger::DEBUG
                   end
require_relative "../lib/request_context"
require_relative "../lib/log_formatter"
APP_LOGGER.formatter = APP_CONFIG.production? ? LogFormatter.json : LogFormatter.tagged
APP_CONFIG.log_boot_summary(APP_LOGGER)

require_relative "database"

LOADER = Zeitwerk::Loader.new
LOADER.inflector.inflect("uuid" => "UUID", "geo_ip" => "GeoIP")
LOADER.push_dir(File.expand_path("../lib", __dir__))
LOADER.push_dir(File.expand_path("../app", __dir__))
LOADER.push_dir(File.expand_path("../app/models", __dir__))
LOADER.push_dir(File.expand_path("../app/serializers", __dir__))
LOADER.push_dir(File.expand_path("../app/services", __dir__))
LOADER.push_dir(File.expand_path("../app/policies", __dir__))
LOADER.ignore(File.expand_path("../app/app.rb", __dir__))
LOADER.ignore(File.expand_path("../app/routes", __dir__))
LOADER.setup
LOADER.eager_load if APP_CONFIG.production?

WebAuthn.configure do |config|
  config.allowed_origins = [APP_CONFIG.frontend_url.to_s, *APP_CONFIG.webauthn_extra_origins]
  config.rp_name = "Tayaway"
  config.rp_id = APP_CONFIG.frontend_url.host
  # We request indirect attestation only to preserve the AAGUID for friendly-name
  # lookup via FIDO MDS. We don't restrict to specific authenticators, so verifying
  # the attestation chain adds no security and would reject any roaming key whose
  # batch cert root we don't ship.
  config.verify_attestation_statement = false
end

# FIDO Metadata Service cache — used to look up authenticator device names by AAGUID.
# File-backed cache persists the MDS blob across restarts so only the first boot after
# deploy fetches from the network. The blob is pre-warmed in a background thread at boot.
FidoMetadata.configure do |config|
  config.cache_backend = FidoCacheStore.new(dir: "#{APP_DIR}/tmp/cache/fido_metadata")
end

# Pre-warm the FIDO metadata cache in a background thread so no user request pays the cost.
if APP_CONFIG.production? || APP_CONFIG.development?
  Thread.new do
    FidoMetadata::Store.new.table_of_contents
    APP_LOGGER.info { "[FidoMetadata] Cache warmed" }
  rescue StandardError => e
    APP_LOGGER.debug { "[FidoMetadata] Cache warm failed: #{e.message}" }
  end
end

Mailers::Base.configure!
RateLimiter.configure!

# The web-push gem hard-codes `http.use_ssl = true`, which means an e2e
# smoke test that points push delivery at a localhost server has to
# present a TLS cert. We use a self-signed cert in that test server, so
# in e2e mode skip peer verification — but only for loopback destinations.
# Scoping by destination keeps real TLS verification on for any other
# outbound HTTPS call this env might gain in the future.
if APP_CONFIG.e2e?
  require "net/http"
  require "openssl"
  require "ipaddr"

  module E2eSkipSslVerify
    LOOPBACK_HOSTS = %w[localhost ip6-localhost].freeze

    def use_ssl=(value)
      super
      self.verify_mode = OpenSSL::SSL::VERIFY_NONE if value && E2eSkipSslVerify.loopback?(address)
    end

    def self.loopback?(host)
      return true if LOOPBACK_HOSTS.include?(host)

      IPAddr.new(host).loopback?
    rescue IPAddr::InvalidAddressError
      false
    end
  end

  Net::HTTP.prepend(E2eSkipSslVerify)
end

require_relative "../app/app"
