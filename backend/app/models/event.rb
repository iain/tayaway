# typed: true
# frozen_string_literal: true

class Event < Sequel::Model
  many_to_one :user
  one_to_many :date_ranges, order: :start_date

  def validate
    super
    validates_presence :name
    validates_max_length 255, :name
    validates_presence :user_id
  end

  def before_save
    self.updated_at = Time.now
    super
  end

  def to_api_hash
    {
      id: id,
      name: name,
      description: description,
      user_id: user_id,
      user: user&.to_api_hash,
      date_ranges: date_ranges.map(&:to_api_hash),
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  def to_pool_hash
    {
      id: id,
      objectType: "event",
      name: name,
      description: description,
      userId: user_id,
      dateRangeIds: date_ranges.map(&:id),
      createdAt: created_at&.iso8601(3),
      updatedAt: updated_at&.iso8601(3)
    }
  end
end
