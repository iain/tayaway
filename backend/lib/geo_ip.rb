# typed: false
# frozen_string_literal: true

# IP geolocation using a DB-IP Lite .mmdb database file.
#
# The DB-IP Lite City database is a free, CC BY 4.0 licensed dataset from
# https://db-ip.com — "IP Geolocation by DB-IP".
#
# The database file is expected at backend/data/dbip-city-lite.mmdb.
# If the file is missing (e.g. in test/CI) all lookups return nil gracefully.
module GeoIP
  MMDB_PATH = T.let(
    File.expand_path("../data/dbip-city-lite.mmdb", __dir__),
    String
  )

  @db = T.let(nil, T.untyped)
  @db_loaded = T.let(false, T::Boolean)

  class << self
    # Returns { city: "Amsterdam", country: "Netherlands" } or nil.
    def lookup(ip)
      db = load_db
      return nil unless db
      return nil if ip.nil? || ip.empty? || local_ip?(ip)

      result = db.lookup(ip)
      return nil unless result

      city = result[:city]
      country = result[:country]
      return nil unless city || country

      { city: city, country: country }
    rescue StandardError
      nil
    end

    private

    def load_db
      return @db if @db_loaded

      @db_loaded = true
      unless File.exist?(MMDB_PATH)
        APP_LOGGER.info { "[GeoIP] No mmdb file at #{MMDB_PATH} — geolocation disabled" }
        return nil
      end

      @db = MaxMindDB.new(MMDB_PATH)
      APP_LOGGER.info { "[GeoIP] Loaded DB-IP database from #{MMDB_PATH}" }
      @db
    rescue StandardError => e
      APP_LOGGER.warn { "[GeoIP] Failed to load mmdb: #{e.message}" }
      nil
    end

    def local_ip?(ip)
      ip == "127.0.0.1" || ip == "::1" || ip.start_with?("10.", "192.168.", "172.")
    end
  end
end
