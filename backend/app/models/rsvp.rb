# typed: true
# frozen_string_literal: true

# Read-only RSVP model.
class Rsvp < T::Struct
  extend T::Sig

  const :id, UUID
  const :event_id, UUID
  const :user_id, UUID
  const :attending, T::Boolean
  const :start_date, T.nilable(Date)
  const :end_date, T.nilable(Date)
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "rsvp",
      eventId: event_id.to_s,
      userId: user_id.to_s,
      attending: attending,
      startDate: start_date&.iso8601,
      endDate: end_date&.iso8601,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(Rsvp)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(event_id: T.any(String, UUID)).returns(T::Array[Rsvp]) }
    def for_event(event_id)
      dataset.where(event_id: event_id).all
    end

    sig { params(event_id: T.any(String, UUID)).returns(T::Array[String]) }
    def ids_for_event(event_id)
      DB[:rsvps].where(event_id: event_id).select_map(:id)
    end

    sig { params(event_ids: T::Array[String]).returns(T::Hash[String, T::Array[String]]) }
    def ids_for_event_ids(event_ids)
      return {} if event_ids.empty?

      DB[:rsvps]
        .where(event_id: event_ids)
        .select_map([:event_id, :id])
        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(event_id, id), h| h[event_id.to_s] << id.to_s }
    end

    sig { params(event_id: T.any(String, UUID), user_id: T.any(String, UUID)).returns(T.nilable(Rsvp)) }
    def find_by_event_and_user(event_id, user_id)
      dataset.where(event_id: event_id, user_id: user_id).first
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[Rsvp]) }
    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id)
        .where(Sequel.lit("rsvps.updated_at > ?", since))
        .select_all(:rsvps)
        .all
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:rsvps].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(Rsvp) }
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
