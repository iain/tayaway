# typed: true
# frozen_string_literal: true

class Vote < Sequel::Model
  many_to_one :date_range
  many_to_one :user

  VALID_RESPONSES = %w[yes no preferably_not].freeze

  def validate
    super
    validates_presence :date_range_id
    validates_presence :user_id
    validates_presence :response
    validates_includes VALID_RESPONSES, :response, message: "must be yes, no, or preferably_not"
  end

  def before_save
    self.updated_at = Time.now
    super
  end

  def to_api_hash
    {
      id: id,
      date_range_id: date_range_id,
      user_id: user_id,
      user: user&.to_api_hash,
      response: response,
      comment: comment,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
end
