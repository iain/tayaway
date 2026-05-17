# frozen_string_literal: true

# IP geolocation using a DB-IP Lite .mmdb database file.
#
# The DB-IP Lite City database is a free, CC BY 4.0 licensed dataset from
# https://db-ip.com — "IP Geolocation by DB-IP".
#
# In production the file lives on a podman volume mounted read-only and is
# refreshed monthly by a separate `geoip.container` oneshot that writes the
# new file under a temp name and atomically renames over the old one. The
# handle is cached by file mtime; each lookup does one stat() and rebuilds
# the handle when the mtime changes, so a refresh is picked up without
# restarting the web container or coordinating between processes. If the
# file is missing (e.g. in test/CI) all lookups return nil.
module GeoIP
  MMDB_PATH = File.expand_path("../data/dbip-city-lite.mmdb", __dir__)

  @db = nil
  @db_mtime = nil

  class << self
    # Returns { city: "Amsterdam", country: "Netherlands" } or nil.
    def lookup(ip)
      db = current_db
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

    def current_db
      mtime = begin
        File.mtime(MMDB_PATH)
      rescue Errno::ENOENT
        nil
      end

      if mtime.nil?
        if @db
          APP_LOGGER.info { "[GeoIP] mmdb file disappeared at #{MMDB_PATH} — geolocation disabled" }
          @db = nil
          @db_mtime = nil
        end
        return nil
      end

      return @db if @db && @db_mtime == mtime

      @db = MaxMindDB.new(MMDB_PATH)
      @db_mtime = mtime
      APP_LOGGER.info { "[GeoIP] Loaded DB-IP database from #{MMDB_PATH} (mtime=#{mtime.iso8601})" }
      @db
    rescue StandardError => e
      APP_LOGGER.warn { "[GeoIP] Failed to load mmdb: #{e.message}" }
      @db = nil
      @db_mtime = nil
      nil
    end

    def local_ip?(ip)
      ip == "127.0.0.1" || ip == "::1" || ip.start_with?("10.", "192.168.", "172.")
    end
  end
end
