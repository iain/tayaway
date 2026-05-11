# frozen_string_literal: true

module Auth
  module SessionCreator
    def self.create(user_id, ip: nil, user_agent: nil)
      now = Time.now
      id = SecureRandom.uuid
      token = SecureRandom.hex(32)
      expires_at = now + Session::EXPIRY_SECONDS

      geo = begin
        ip ? GeoIP.lookup(ip) : nil
      rescue StandardError => e
        APP_LOGGER.warn { "[Auth::SessionCreator] GeoIP lookup failed for #{ip.inspect}: #{e.class}" }
        nil
      end
      browser_info = user_agent ? parse_user_agent(user_agent) : nil
      ip_addr = begin
        ip && IPAddr.new(ip)
      rescue IPAddr::Error => e
        APP_LOGGER.warn { "[Auth::SessionCreator] Invalid IP address #{ip.inspect}: #{e.message}" }
        nil
      end

      DB[:sessions].insert(
        id: id,
        user_id: user_id,
        token: Auth::Token.digest(token),
        expires_at: expires_at,
        created_at: now,
        ip_address: ip_addr,
        city: geo&.dig(:city),
        country: geo&.dig(:country),
        browser_name: browser_info&.dig(:browser_name),
        os_name: browser_info&.dig(:os_name)
      )

      APP_LOGGER.info { "[Auth::SessionCreator] Session created for user #{user_id}" }
      Auth::OnNewSession.call(user_id: user_id, session_id: id, browser_info: browser_info, geo: geo)
      { session_token: token, user_id: user_id }
    end

    def self.parse_user_agent(user_agent)
      b = Browser.new(user_agent)
      {
        browser_name: b.name.empty? ? nil : b.name,
        os_name: b.platform.name.empty? ? nil : b.platform.name
      }
    rescue StandardError
      { browser_name: nil, os_name: nil }
    end
  end
end
