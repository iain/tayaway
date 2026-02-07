# typed: true
# frozen_string_literal: true

class DateRange < Sequel::Model
  many_to_one :event
  one_to_many :votes

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
      end_date: end_date&.iso8601,
      votes: votes.map(&:to_api_hash),
      vote_summary: vote_summary
    }
  end

  def vote_summary
    counts = { "yes" => 0, "no" => 0, "preferably_not" => 0 }
    votes.each { |v| counts[v.response] += 1 }
    {
      yes: counts["yes"],
      no: counts["no"],
      preferably_not: counts["preferably_not"],
      total: votes.count
    }
  end

  def to_pool_hash
    {
      id: id,
      objectType: "dateRange",
      eventId: event_id,
      startDate: start_date&.iso8601,
      endDate: end_date&.iso8601,
      voteIds: votes.map(&:id),
      updatedAt: updated_at&.iso8601(3)
    }
  end
end
