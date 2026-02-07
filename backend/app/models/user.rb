# typed: true
# frozen_string_literal: true

# Read-only user model.
class User < T::Struct
  extend T::Sig

  const :id, UUID
  const :email, EmailAddress
  const :name, T.nilable(String)
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "user",
      email: email.to_s,
      name: name,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(User)) }
    def find(id)
      DB[:users].where(id: id).with_row_proc(method(:from_row)).first
    end

    sig { params(email: T.any(String, EmailAddress)).returns(T.nilable(User)) }
    def find_by_email(email)
      DB[:users].where(Sequel.lit("LOWER(email) = ?", email.to_s.downcase)).with_row_proc(method(:from_row)).first
    end

    sig { params(email: T.any(String, EmailAddress)).returns(T.nilable(User)) }
    def find_by_email_exact(email)
      DB[:users].where(email: email).with_row_proc(method(:from_row)).first
    end

    sig { returns(T::Array[User]) }
    def all_ordered
      DB[:users].order(:name, :email).with_row_proc(method(:from_row)).all
    end

    private

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(User) }
    def from_row(row)
      User.new(
        id: UUID.new(row[:id]),
        email: EmailAddress.new(row[:email]),
        name: row[:name],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
