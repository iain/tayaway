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
      notify_if_new(user_id, id, browser_info, geo)
      { session_token: token, user_id: user_id }
    end

    # Fires `:new_session` only when this (browser, country) combination
    # is novel for the user in the last 30 days. The first session a user
    # ever has trips it (welcome and confirmation that login worked); a
    # repeat sign-in from the same browser and country stays quiet.
    def self.notify_if_new(user_id, session_id, browser_info, geo)
      Notifications::Safely.deliver(context: "Auth::SessionCreator") do
        browser_name = browser_info&.dig(:browser_name)
        country = geo&.dig(:country)

        seen_before = DB[:sessions]
                      .where(user_id: user_id)
                      .exclude(id: session_id)
                      .where(browser_name: browser_name, country: country)
                      .where { created_at >= (Time.now - (30 * 86_400)) }
                      .any?
        return if seen_before

        user = User.find(user_id)
        return unless user

        Notifications::Dispatch.call(
          kind: :new_session,
          user_id: user_id.to_s,
          data: {
            email: user.email.to_s,
            recipient_name: user.name,
            browser_name: browser_name,
            os_name: browser_info&.dig(:os_name),
            city: geo&.dig(:city),
            country: country,
            session_url: "#{ENV.fetch("FRONTEND_URL", "https://tayaway.nl")}/settings/login"
          }
        )
      end
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
