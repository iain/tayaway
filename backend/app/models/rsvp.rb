# frozen_string_literal: true

# Read-only RSVP model.
class Rsvp
  attr_reader :id, :event_id, :user_id, :attending, :start_date, :end_date, :created_at, :updated_at

  def initialize(
    id:,
    event_id:,
    user_id:,
    attending:,
    start_date:,
    end_date:,
    created_at:,
    updated_at:
  )
    @id = id
    @event_id = event_id
    @user_id = user_id
    @attending = attending
    @start_date = start_date
    @end_date = end_date
    @created_at = created_at
    @updated_at = updated_at
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
      Rsvp.new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        user_id: UUID.new(row[:user_id]),
        attending: row[:attending],
        start_date: row[:start_date],
        end_date: row[:end_date],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
