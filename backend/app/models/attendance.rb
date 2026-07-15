# frozen_string_literal: true

# Read-only attendance model: one row per person (member or guest) per event.
# Rows are long-lived — status transitions instead of deletion — so presence-
# side tables can FK into them without history rewrites (doc/attendances.md).
class Attendance < Data.define(:id, :event_id, :user_id, :guest_id, :host_user_id, :status, :days, :created_by_user_id, :created_at, :updated_at)
  def going?
    status == "going"
  end

  def guest?
    !guest_id.nil?
  end

  # The concrete set of days this row covers, resolved against its event:
  # the explicit day set when present, otherwise the whole event. Only
  # meaningful when going — pending/declined rows keep days NULL and presence
  # math never reads them.
  def effective_days(event)
    days || (event.start_date..event.end_date).to_a
  end

  # The single backend reader of the user/guest union. Loads the person's
  # name with one query; batch consumers should prefetch and build Attendee
  # instances themselves if this ever shows up in a hot path.
  def attendee
    if guest?
      Attendee.new(display_name: Guest.find(guest_id)&.name, user_id: nil, guest_id: guest_id, host_user_id: host_user_id)
    else
      Attendee.new(display_name: DB[:users].where(id: user_id).get(:name), user_id: user_id, guest_id: nil, host_user_id: nil)
    end
  end

  class << self
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_event(event_id)
      dataset.where(event_id: event_id).all
    end

    def ids_for_event(event_id)
      DB[:attendances].where(event_id: event_id).select_map(:id)
    end

    def ids_for_event_ids(event_ids)
      return {} if event_ids.empty?

      DB[:attendances]
        .where(event_id: event_ids)
        .select_map([:event_id, :id])
        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(event_id, id), h| h[event_id.to_s] << id.to_s }
    end

    def find_by_event_and_user(event_id, user_id)
      dataset.where(event_id: event_id, user_id: user_id).first
    end

    def find_by_event_and_guest(event_id, guest_id)
      dataset.where(event_id: event_id, guest_id: guest_id).first
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id)
        .where(Sequel.lit("attendances.updated_at > ?", since))
        .select_all(:attendances)
        .all
    end

    private

    def dataset
      DB[:attendances].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        guest_id: row[:guest_id] ? UUID.new(row[:guest_id]) : nil,
        host_user_id: row[:host_user_id] ? UUID.new(row[:host_user_id]) : nil,
        status: row[:status],
        days: parse_days(row[:days]),
        created_by_user_id: row[:created_by_user_id] ? UUID.new(row[:created_by_user_id]) : nil,
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end

    # Parse the JSONB day set (flat ISO strings) into sorted dates, or nil for
    # "whole event". An empty array is treated as nil (no restriction).
    def parse_days(value)
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

      array.map { |entry| entry.is_a?(Date) ? entry : Date.parse(entry.to_s) }.sort
    end
  end
end
