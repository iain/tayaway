# frozen_string_literal: true

# Read-only RSVP model.
class Rsvp < Data.define(:id, :event_id, :user_id, :created_by_user_id, :attending, :attendance, :start_date, :end_date, :created_at, :updated_at)
  # The concrete set of days this RSVP covers, resolved against its event.
  # `attendance` (an explicit "come and go" day set) wins; otherwise the legacy
  # contiguous start_date..end_date window; otherwise the whole event. Returns
  # an Array<Date>, dropping any per-day guest counts.
  def effective_dates(event)
    effective_attendance(event).map { |day| day[:date] }
  end

  # The concrete day set with per-day head counts, resolved against its event:
  # `[{ date: Date, plus_ones: Integer }]`, sorted by date. Whole-event and
  # legacy-range RSVPs carry no guests (`plus_ones: 0`); only an explicit
  # `attendance` day set can. This is the unit the settlement split divides on —
  # each day is worth `1 + plus_ones` heads.
  def effective_attendance(event)
    if attendance
      attendance
    elsif start_date && end_date
      (start_date..end_date).map { |date| { date: date, plus_ones: 0 } }
    else
      (event.start_date..event.end_date).map { |date| { date: date, plus_ones: 0 } }
    end
  end

  class << self
    # The wire/JSONB shape for one attendance day (`{ date:, plus_ones: }`): a
    # bare ISO string when guest-free — unchanged from the original come-and-go
    # shape, so existing rows and pre-plus-ones clients keep reading it — and the
    # `{ date, plusOnes }` object only when guests come that day. Defined once
    # here so the serializer (API payload) and Rsvps::Upsert (JSONB persistence)
    # can't drift out of sync.
    def wire_attendance_day(day)
      if day[:plus_ones].positive?
        { date: day[:date].iso8601, plusOnes: day[:plus_ones] }
      else
        day[:date].iso8601
      end
    end

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

    # Parse the JSONB `attendance` array into a sorted
    # `[{ date: Date, plus_ones: Integer }]`, or nil for "whole event". An empty
    # array is treated as nil (no restriction). Tolerant of two entry shapes:
    # the legacy flat ISO string `"2026-07-01"` (no guests) and the current
    # object form `{ "date" => "2026-07-01", "plusOnes" => 2 }`.
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

      array.map { |entry| parse_attendance_entry(entry) }.sort_by { |day| day[:date] }
    end

    def parse_attendance_entry(entry)
      if entry.is_a?(Hash)
        date = entry["date"] || entry[:date]
        plus_ones = entry["plusOnes"] || entry[:plusOnes] || 0
        { date: coerce_date(date), plus_ones: plus_ones.to_i }
      else
        { date: coerce_date(entry), plus_ones: 0 }
      end
    end

    def coerce_date(value)
      value.is_a?(Date) ? value : Date.parse(value.to_s)
    end
  end
end
