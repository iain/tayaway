# frozen_string_literal: true

# Read-only Settlement model.
class Settlement
  attr_reader :id, :event_id, :user_id, :previous_settlement_id, :rsvp_snapshot, :created_at, :updated_at

  def initialize(
    id:,
    event_id:,
    user_id:,
    created_at:,
    updated_at:,
    previous_settlement_id: nil,
    rsvp_snapshot: nil
  )
    @id = id
    @event_id = event_id
    @user_id = user_id
    @previous_settlement_id = previous_settlement_id
    @rsvp_snapshot = rsvp_snapshot
    @created_at = created_at
    @updated_at = updated_at
  end

  class << self
    include Dry::Monads[:result]
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_event(event_id)
      dataset.where(event_id: event_id).order(:created_at).all
    end

    # The tip is the unique settlement for the event that no other settlement
    # references via previous_settlement_id. "Most recently created" is only a
    # proxy; this definition is the structural one, enforced by the unique
    # partial index on previous_settlement_id.
    def tip_for_event(event_id)
      dataset
        .where(event_id: event_id)
        .exclude(
          id: DB[:settlements]
              .where(event_id: event_id)
              .exclude(previous_settlement_id: nil)
              .select(:previous_settlement_id)
        )
        .first
    end

    def chain_for(settlement_id)
      result = []
      current = find(settlement_id)
      while current
        result.unshift(current)
        current = current.previous_settlement_id ? find(current.previous_settlement_id) : nil
      end
      result
    end

    def successor?(settlement_id)
      DB[:settlements].where(previous_settlement_id: settlement_id).any?
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("settlements.updated_at > ?", since))
        .select_all(:settlements)
        .all
    end

    private

    def dataset
      DB[:settlements].with_row_proc(method(:from_row))
    end

    def from_row(row)
      Settlement.new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        previous_settlement_id: row[:previous_settlement_id] ? UUID.new(row[:previous_settlement_id]) : nil,
        rsvp_snapshot: parse_snapshot(row[:rsvp_snapshot]),
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end

    def parse_snapshot(value)
      return nil if value.nil?
      return value.to_h if value.is_a?(Sequel::Postgres::JSONBObject)
      return value if value.is_a?(Hash)
      return JSON.parse(value) if value.is_a?(String)

      raise TypeError, "Unexpected rsvp_snapshot type: #{value.class}"
    end
  end
end
