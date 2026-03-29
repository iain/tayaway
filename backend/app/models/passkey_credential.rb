# typed: true
# frozen_string_literal: true

class PasskeyCredential < T::Struct
  extend T::Sig

  const :id, UUID
  const :user_id, UUID
  const :external_id, String
  const :public_key, String
  const :sign_count, Integer
  const :aaguid, T.nilable(String)
  const :name, T.nilable(String)
  const :created_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      name: name,
      aaguid: aaguid,
      createdAt: created_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(PasskeyCredential)) }
    def find(id)
      dataset.where(id: id.to_s).first
    end

    sig { params(external_id: String).returns(T.nilable(PasskeyCredential)) }
    def find_by_external_id(external_id)
      dataset.where(external_id: external_id).first
    end

    sig { params(user_id: T.any(String, UUID)).returns(T::Array[PasskeyCredential]) }
    def for_user(user_id)
      dataset
        .where(user_id: user_id.to_s)
        .order(Sequel.desc(:created_at))
        .limit(ValidationLimits::QUERY_LIMIT)
        .all
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:passkey_credentials].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(PasskeyCredential) }
    def from_row(row)
      PasskeyCredential.new(
        id: UUID.new(row[:id]),
        user_id: UUID.new(row[:user_id]),
        external_id: row[:external_id],
        public_key: row[:public_key],
        sign_count: row[:sign_count],
        aaguid: row[:aaguid],
        name: row[:name],
        created_at: row[:created_at]
      )
    end
  end
end
