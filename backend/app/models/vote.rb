# frozen_string_literal: true

# Read-only vote model.
class Vote < Data.define(:id, :date_range_id, :user_id, :response, :comment, :created_at, :updated_at)
  include PoolSerializable

  pool_object client_type: "vote"

  class << self
    def find(id)
      dataset.where(id: id).first
    end

    def for_date_range(date_range_id)
      dataset.where(date_range_id: date_range_id).all
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:date_ranges, id: :date_range_id)
        .join(:date_polls, id: Sequel[:date_ranges][:date_poll_id])
        .join(:events, id: Sequel[:date_polls][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id)
        .where(Sequel.lit("votes.updated_at > ?", since))
        .select_all(:votes)
        .all
    end

    def for_date_range_ids(date_range_ids)
      return [] if date_range_ids.empty?

      dataset.where(date_range_id: date_range_ids).all
    end

    def find_by_date_range_and_user(date_range_id, user_id)
      dataset.where(date_range_id: date_range_id, user_id: user_id).first
    end

    private

    def dataset
      DB[:votes].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        date_range_id: UUID.new(row[:date_range_id]),
        user_id: UUID.new(row[:user_id]),
        response: row[:response],
        comment: row[:comment],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
