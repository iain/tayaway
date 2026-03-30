# typed: true
# frozen_string_literal: true

module Auth
  module SessionCreator
    extend T::Sig

    sig do
      params(user_id: String, ip: T.nilable(String), user_agent: T.nilable(String))
        .returns(T::Hash[Symbol, T.untyped])
    end
    def self.create(user_id, ip: nil, user_agent: nil)
      now = Time.now
      id = SecureRandom.uuid
      token = SecureRandom.hex(32)
      expires_at = now + Session::EXPIRY_SECONDS

      geo = ip ? GeoIP.lookup(ip) : nil
      browser_info = user_agent ? parse_user_agent(user_agent) : nil

      DB[:sessions].insert(
        id: id,
        user_id: user_id,
        token: Auth::Token.digest(token),
        expires_at: expires_at,
        created_at: now,
        ip_address: ip && IPAddr.new(ip),
        city: geo&.dig(:city),
        country: geo&.dig(:country),
        browser_name: browser_info&.dig(:browser_name),
        os_name: browser_info&.dig(:os_name)
      )

      { session_token: token, user_id: user_id }
    end

    sig { params(user_agent: String).returns(T::Hash[Symbol, T.nilable(String)]) }
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
