# typed: true
# frozen_string_literal: true

class User < Sequel::Model
  one_to_many :magic_link_tokens
  one_to_many :sessions
  one_to_many :events
  one_to_many :votes

  def validate
    super
    validates_presence :email
    validates_unique :email
    validates_format(/\A[^@\s]+@[^@\s]+\z/, :email, message: "is not a valid email")
  end

  def to_api_hash
    {
      id: id,
      email: email,
      name: name,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  def to_pool_hash
    {
      id: id,
      objectType: "user",
      email: email,
      name: name,
      createdAt: created_at&.iso8601(3),
      updatedAt: updated_at&.iso8601(3)
    }
  end
end
