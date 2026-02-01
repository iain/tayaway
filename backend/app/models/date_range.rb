# typed: true
# frozen_string_literal: true

class DateRange < Sequel::Model
  many_to_one :event

  def validate
    super
    validates_presence :start_date
    validates_presence :end_date
    validates_presence :event_id

    if start_date && end_date && end_date < start_date
      errors.add(:end_date, "must be on or after start date")
    end
  end

  def before_save
    self.updated_at = Time.now
    super
  end

  def to_api_hash
    {
      id: id,
      start_date: start_date&.iso8601,
      end_date: end_date&.iso8601
    }
  end
end
