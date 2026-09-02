# frozen_string_literal: true

# Read-only date range model.
class DateRange < Data.define(:id, :date_poll_id, :start_date, :end_date, :created_at, :updated_at)
  class << self
    def find(id)
      dataset.where(id: id).first
    end

    def for_date_poll(date_poll_id)
      dataset.where(date_poll_id: date_poll_id).order(:start_date).all
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:date_polls, id: :date_poll_id)
        .join(:events, id: Sequel[:date_polls][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id)
        .where(Sequel.lit("date_ranges.updated_at > ?", since))
        .select_all(:date_ranges)
        .all
    end

    def ids_for_date_poll(date_poll_id)
      DB[:date_ranges].where(date_poll_id: date_poll_id).order(:start_date).select_map(:id)
    end

    def ids_for_date_poll_ids(date_poll_ids)
      return {} if date_poll_ids.empty?

      DB[:date_ranges]
        .where(date_poll_id: date_poll_ids)
        .order(:start_date)
        .select_map([:date_poll_id, :id])
        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(poll_id, id), h| h[poll_id.to_s] << id.to_s }
    end

    def count_for_date_poll(date_poll_id)
      DB[:date_ranges].where(date_poll_id: date_poll_id).count
    end

    def counts_for_date_poll_ids(date_poll_ids)
      return {} if date_poll_ids.empty?

      DB[:date_ranges]
        .where(date_poll_id: date_poll_ids)
        .group_and_count(:date_poll_id)
        .to_hash(:date_poll_id, :count)
        .transform_keys(&:to_s)
    end

    private

    def dataset
      DB[:date_ranges].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        date_poll_id: UUID.new(row[:date_poll_id]),
        start_date: row[:start_date],
        end_date: row[:end_date],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
