# frozen_string_literal: true

# Read-only RSVP model.
class Rsvp < Data.define(:id, :event_id, :user_id, :created_by_user_id, :attending, :attendance, :start_date, :end_date, :created_at, :updated_at)
  # The concrete set of days this RSVP covers, resolved against its event.
  # `attendance` (an explicit "come and go" day set) wins; otherwise the legacy
  # contiguous start_date..end_date window; otherwise the whole event. Returns
  # an Array<Date>.
  def effective_dates(event)
    if attendance
      attendance
    elsif start_date && end_date
      (start_date..end_date).to_a
    else
      (event.start_date..event.end_date).to_a
    end
  end

  class << self
    def find(id)
      dataset.where(id: id).first
    end

    def for_event(event_id)
      dataset.where(event_id: event_id).all
    end

    def ids_for_event(event_id)
      DB[:rsvps].where(event_id: event_id).select_map(:id)
    end

    def ids_for_event_ids(event_ids)
      return {} if event_ids.empty?

      DB[:rsvps]
        .where(event_id: event_ids)
        .select_map([:event_id, :id])
        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(event_id, id), h| h[event_id.to_s] << id.to_s }
    end

    def find_by_event_and_user(event_id, user_id)
      dataset.where(event_id: event_id, user_id: user_id).first
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id)
        .where(Sequel.lit("rsvps.updated_at > ?", since))
        .select_all(:rsvps)
        .all
    end

    private

    def dataset
      DB[:rsvps].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        user_id: UUID.new(row[:user_id]),
        created_by_user_id: row[:created_by_user_id] ? UUID.new(row[:created_by_user_id]) : nil,
        attending: row[:attending],
        attendance: parse_attendance(row[:attendance]),
        start_date: row[:start_date],
        end_date: row[:end_date],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end

    # Parse the JSONB `attendance` array into sorted Array<Date>, or nil for
    # "whole event". An empty array is treated as nil (no restriction).
    def parse_attendance(value)
      return nil if value.nil?

      array =
        if value.is_a?(String)
          JSON.parse(value)
        elsif value.respond_to?(:to_a)
          value.to_a
        else
          value
        end
      return nil unless array.is_a?(Array) && array.any?

      array.map { |d| d.is_a?(Date) ? d : Date.parse(d.to_s) }.sort
    end
  end
end
