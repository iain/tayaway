# typed: true
# frozen_string_literal: true

# Read-only session model.
class Session < T::Struct
  extend T::Sig

  EXPIRY_DAYS = 30
  EXPIRY_SECONDS = EXPIRY_DAYS * 24 * 60 * 60
  INACTIVITY_SECONDS = 7 * 24 * 60 * 60 # 7 days
  ACTIVITY_THROTTLE_SECONDS = 5 * 60 # 5 minutes

  const :id, UUID
  const :user_id, UUID
  const :token, String
  const :expires_at, Time
  const :last_active_at, T.nilable(Time)
  const :created_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      created_at: created_at.iso8601,
      expires_at: expires_at.iso8601,
      last_active_at: last_active_at&.iso8601
    }
  end

  sig { returns(T::Boolean) }
  def inactive?
    return false unless last_active_at

    last_active_at < Time.now - INACTIVITY_SECONDS
  end

  sig { returns(T::Boolean) }
  def activity_update_needed?
    return true unless last_active_at

    last_active_at < Time.now - ACTIVITY_THROTTLE_SECONDS
  end

  class << self
    extend T::Sig

    sig { params(token: String).returns(T.nilable(Session)) }
    def find_valid(token)
      session = dataset
                .where(token: Auth::Token.digest(token))
                .where(Sequel[:expires_at] > Time.now)
                .first
      return nil if session&.inactive?

      session
    end

    sig { params(token: String).returns(T.nilable(Session)) }
    def find_by_token(token)
      dataset.where(token: Auth::Token.digest(token)).first
    end

    sig { params(id: String).returns(T.nilable(Session)) }
    def find_valid_by_id(id)
      session = dataset
                .where(id: id)
                .where(Sequel[:expires_at] > Time.now)
                .first
      return nil if session&.inactive?

      session
    end

    sig { params(user_id: UUID).returns(T::Array[Session]) }
    def for_user(user_id)
      dataset
        .where(user_id: user_id.to_s)
        .where(Sequel[:expires_at] > Time.now)
        .order(Sequel.desc(:created_at))
        .all
        .reject(&:inactive?)
    end

    sig { params(session: Session).void }
    def touch_activity(session)
      return unless session.activity_update_needed?

      DB.transaction(savepoint: true) do
        DB[:sessions].where(id: session.id.to_s).update(last_active_at: Time.now)
      end
    rescue Sequel::DatabaseError
      # Silently ignore — the session may reference a deleted user (race condition).
      # The savepoint ensures the outer transaction is not aborted.
      nil
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:sessions].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(Session) }
    def from_row(row)
      Session.new(
        id: UUID.new(row[:id]),
        user_id: UUID.new(row[:user_id]),
        token: row[:token],
        expires_at: row[:expires_at],
        last_active_at: row[:last_active_at],
        created_at: row[:created_at]
      )
    end
  end
end
