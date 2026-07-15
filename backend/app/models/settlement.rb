# frozen_string_literal: true

# Read-only Settlement model.
class Settlement < Data.define(:id, :event_id, :user_id, :previous_settlement_id, :rsvp_snapshot, :created_at, :updated_at)
  class << self
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_event(event_id)
      dataset.where(event_id: event_id).order(:created_at).all
    end

    # The tip is the unique settlement for the event that no other settlement
    # references via previous_settlement_id. Uniqueness is enforced at the DB
    # layer by the partial indexes on previous_settlement_id and event_id.
    def tip_for_event(event_id)
      dataset
        .where(event_id: event_id)
        .exclude(
          id: DB[:settlements]
              .where(event_id: event_id)
              .exclude(previous_settlement_id: nil)
              .select(:previous_settlement_id)
        )
        .order(Sequel.desc(:created_at))
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
      new(
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

      parsed =
        if value.is_a?(Sequel::Postgres::JSONBObject)
          value.to_h
        elsif value.is_a?(Hash)
          value
        elsif value.is_a?(String)
          JSON.parse(value)
        else
          raise "Unexpected rsvp_snapshot type: #{value.class}"
        end

      entries = parsed["attendances"] || parsed["rsvps"]
      raise "rsvp_snapshot missing 'attendances' or 'rsvps' array" unless entries.is_a?(Array)
      # Snapshots have carried four shapes over time; accept all so historical
      # settlements stay readable: the current per-attendance form (flat `days`
      # billing a `billing_user_id`; guests are their own entries), the rsvp
      # `days` day set (each entry an object with per-day `plus_ones`), the
      # earlier flat `dates` array, and the oldest start_date/end_date range.
      entries.each do |entry|
        has_user = entry.is_a?(Hash) && (!entry["user_id"].nil? || !entry["billing_user_id"].nil?)
        has_days = entry.is_a?(Hash) && entry["days"].is_a?(Array)
        has_dates = entry.is_a?(Hash) && entry["dates"].is_a?(Array)
        has_range = entry.is_a?(Hash) && !entry["start_date"].nil? && !entry["end_date"].nil?
        unless has_user && (has_days || has_dates || has_range)
          raise "rsvp_snapshot entry is malformed: #{entry.inspect}"
        end
      end

      parsed
    end
  end
end
