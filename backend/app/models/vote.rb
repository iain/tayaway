# typed: true
# frozen_string_literal: true

class Vote < Sequel::Model
  # Allow client-generated UUIDs for optimistic updates
  unrestrict_primary_key

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

  def to_pool_hash
    {
      id: id,
      objectType: "vote",
      dateRangeId: date_range_id,
      userId: user_id,
      response: response,
      comment: comment,
      createdAt: created_at&.iso8601(3),
      updatedAt: updated_at&.iso8601(3)
    }
  end
end
