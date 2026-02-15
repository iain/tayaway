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
      dataset.where(id: id).first
    end

    sig { params(email: T.any(String, EmailAddress)).returns(T.nilable(User)) }
    def find_by_email(email)
      dataset.where(Sequel.lit("LOWER(email) = ?", email.to_s.downcase)).first
    end

    sig { params(email: T.any(String, EmailAddress)).returns(T.nilable(User)) }
    def find_by_email_exact(email)
      dataset.where(email: email).first
    end

    sig { params(ids: T::Array[T.any(String, UUID)]).returns(T::Array[User]) }
    def for_ids(ids)
      return [] if ids.empty?

      dataset.where(id: ids).all
    end

    sig { returns(T::Array[User]) }
    def all_ordered
      dataset.order(:name, :email).all
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:users].with_row_proc(method(:from_row))
    end

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
