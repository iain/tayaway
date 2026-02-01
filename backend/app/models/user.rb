# typed: true
# frozen_string_literal: true

class User < Sequel::Model
  one_to_many :magic_link_tokens
  one_to_many :sessions

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
end
