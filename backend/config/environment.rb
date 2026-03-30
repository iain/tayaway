# typed: true
# frozen_string_literal: true

VALID_ENVIRONMENTS = %w[production development test e2e].freeze
APP_ENV = ENV.fetch("RACK_ENV", "development")
unless VALID_ENVIRONMENTS.include?(APP_ENV)
  raise "Invalid RACK_ENV=#{APP_ENV.inspect}. Must be one of: #{VALID_ENVIRONMENTS.join(", ")}"
end
APP_DIR = Pathname(File.expand_path("..", __dir__))

require "bundler/setup"
Bundler.require(:default, APP_ENV)

GIT_SHA = T.let(
  (
    ENV["GIT_SHA"] ||
    (File.read("#{APP_DIR}/REVISION").strip[0, 7] if File.exist?("#{APP_DIR}/REVISION")) ||
    `git rev-parse --short HEAD 2>/dev/null`.strip
  ).freeze,
  String,
)

Dotenv.overload("#{APP_DIR}/.env.#{APP_ENV}") unless APP_ENV == "production"

require "base64"
APP_SECRET = Base64.strict_decode64(ENV.fetch("APP_SECRET"))

require "logger"
APP_LOGGER = Logger.new($stdout)
APP_LOGGER.level = case APP_ENV
                   when "production" then Logger::INFO
                   when "test" then Logger::FATAL
                   when "e2e" then Logger::WARN
                   else Logger::DEBUG
                   end
APP_LOGGER.formatter = if APP_ENV == "production"
                         proc { |severity, time, _progname, msg|
                           JSON.generate({ timestamp: time.utc.iso8601(3), level: severity, message: msg.to_s }) + "\n"
                         }
                       else
                         proc { |severity, _time, _progname, msg|
                           label = severity == "DEBUG" ? "" : "[#{severity}] "
                           "#{label}#{msg}\n"
                         }
                       end

require_relative "database"

LOADER = Zeitwerk::Loader.new
LOADER.inflector.inflect("uuid" => "UUID", "geo_ip" => "GeoIP")
LOADER.push_dir(File.expand_path("../lib", __dir__))
LOADER.push_dir(File.expand_path("../app", __dir__))
LOADER.push_dir(File.expand_path("../app/models", __dir__))
LOADER.push_dir(File.expand_path("../app/serializers", __dir__))
LOADER.push_dir(File.expand_path("../app/services", __dir__))
LOADER.ignore(File.expand_path("../app/app.rb", __dir__))
LOADER.ignore(File.expand_path("../app/routes", __dir__))
LOADER.ignore(File.expand_path("../lib/reloading.rb", __dir__))
LOADER.enable_reloading if APP_ENV == "development"
LOADER.setup
LOADER.eager_load if APP_ENV == "production"

FRONTEND_URL = T.let(ENV.fetch("FRONTEND_URL", "http://localhost:5173").freeze, String)

WEBAUTHN_EXTRA_ORIGINS = T.let(
  ENV.fetch("WEBAUTHN_EXTRA_ORIGINS", "").split(",").map(&:strip).reject(&:empty?).freeze,
  T::Array[String],
)

WebAuthn.configure do |config|
  config.allowed_origins = [FRONTEND_URL, *WEBAUTHN_EXTRA_ORIGINS]
  config.rp_name = "Tayaway"
  config.rp_id = URI.parse(FRONTEND_URL).host
end

# FIDO Metadata Service cache — used to look up authenticator device names by AAGUID.
# In-memory cache: each process fetches the MDS blob once and caches it for its lifetime.
# This is acceptable because device-name lookup is best-effort and non-critical.
# Note: TestCacheStore is the gem's name for a simple in-memory hash — it is intentionally
# used here despite the "test" prefix. No file-backed or Redis cache is needed.
require "fido_metadata/test_cache_store"
FIDO_METADATA_CACHE = T.let(FidoMetadata::TestCacheStore.new, FidoMetadata::TestCacheStore)
FidoMetadata.configure do |config|
  config.cache_backend = FIDO_METADATA_CACHE
end

Mailers::Base.configure!
RateLimiter.configure!

require_relative "../app/app"
