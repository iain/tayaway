# frozen_string_literal: true

# Read-only session model.
class Session
  EXPIRY_DAYS = 30
  EXPIRY_SECONDS = EXPIRY_DAYS * 24 * 60 * 60
  INACTIVITY_SECONDS = 7 * 24 * 60 * 60 # 7 days
  ACTIVITY_THROTTLE_SECONDS = 5 * 60 # 5 minutes

  attr_reader :id, :user_id, :token, :expires_at, :last_active_at, :created_at, :ip_address, :city, :country, :browser_name, :os_name

  def initialize(
    id:,
    user_id:,
    token:,
    expires_at:,
    last_active_at:,
    created_at:,
    ip_address:,
    city:,
    country:,
    browser_name:,
    os_name:
  )
    @id = id
    @user_id = user_id
    @token = token
    @expires_at = expires_at
    @last_active_at = last_active_at
    @created_at = created_at
    @ip_address = ip_address
    @city = city
    @country = country
    @browser_name = browser_name
    @os_name = os_name
  end

  def to_api_hash
    {
      id: id.to_s,
      created_at: created_at.iso8601,
      expires_at: expires_at.iso8601,
      last_active_at: last_active_at&.iso8601,
      city: city,
      country: country,
      browser_name: browser_name,
      os_name: os_name
    }
  end

  def inactive?
    return false unless last_active_at

    Time.now - last_active_at > INACTIVITY_SECONDS
  end

  def activity_update_needed?
    return true unless last_active_at

    Time.now - last_active_at > ACTIVITY_THROTTLE_SECONDS
  end

  class << self
    def find_valid(token)
      session = dataset
                .where(token: Auth::Token.digest(token))
                .where(Sequel[:expires_at] > Time.now)
                .first
      return nil if session&.inactive?

      session
    end

    def find_by_token(token)
      dataset.where(token: Auth::Token.digest(token)).first
    end

    def find_valid_by_id(id)
      session = dataset
                .where(id: id)
                .where(Sequel[:expires_at] > Time.now)
                .first
      return nil if session&.inactive?

      session
    end

    def for_user(user_id)
      dataset
        .where(user_id: user_id.to_s)
        .where(Sequel[:expires_at] > Time.now)
        .order(Sequel.desc(:created_at))
        .limit(ValidationLimits::QUERY_LIMIT)
        .all
        .reject(&:inactive?)
    end

    def touch_activity(session)
      return unless session.activity_update_needed?

      # Intentionally updates only the DB row; the in-memory `session` struct
      # remains stale. This is fine — the struct is not reused after the touch.
      DB.transaction(savepoint: true) do
        DB[:sessions].where(id: session.id.to_s).update(last_active_at: Time.now)
      end
    rescue Sequel::DatabaseError
      # Silently ignore — the session may reference a deleted user (race condition).
      # The savepoint ensures the outer transaction is not aborted.
      nil
    end

    private

    def dataset
      DB[:sessions].with_row_proc(method(:from_row))
    end

    def from_row(row)
      Session.new(
        id: UUID.new(row[:id]),
        user_id: UUID.new(row[:user_id]),
        token: row[:token],
        expires_at: row[:expires_at],
        last_active_at: row[:last_active_at],
        created_at: row[:created_at],
        ip_address: row[:ip_address] && IPAddr.new(row[:ip_address].to_s),
        city: row[:city],
        country: row[:country],
        browser_name: row[:browser_name],
        os_name: row[:os_name]
      )
    end
  end
end
