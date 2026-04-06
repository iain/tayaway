# frozen_string_literal: true

class PasskeyCredential
  attr_reader :id, :user_id, :external_id, :public_key, :sign_count, :aaguid, :name, :created_at

  def initialize(
    id:,
    user_id:,
    external_id:,
    public_key:,
    sign_count:,
    aaguid:,
    name:,
    created_at:
  )
    @id = id
    @user_id = user_id
    @external_id = external_id
    @public_key = public_key
    @sign_count = sign_count
    @aaguid = aaguid
    @name = name
    @created_at = created_at
  end

  def to_api_hash
    {
      id: id.to_s,
      name: name,
      aaguid: aaguid,
      createdAt: created_at.iso8601(3)
    }
  end

  class << self
    def find(id)
      dataset.where(id: id.to_s).first
    end

    def find_by_external_id(external_id)
      dataset.where(external_id: external_id).first
    end

    def for_user(user_id)
      dataset
        .where(user_id: user_id.to_s)
        .order(Sequel.desc(:created_at))
        .limit(ValidationLimits::QUERY_LIMIT)
        .all
    end

    private

    def dataset
      DB[:passkey_credentials].with_row_proc(method(:from_row))
    end

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
