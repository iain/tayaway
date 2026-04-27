# frozen_string_literal: true

# Read-only SettlementTransfer model.
class SettlementTransfer < Data.define(:id, :settlement_id, :from_user_id, :to_user_id, :amount, :paid_at, :superseded_at, :created_at, :updated_at)
  class << self
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_settlement(settlement_id)
      dataset.where(settlement_id: settlement_id).order(:created_at).all
    end

    def for_settlement_ids(settlement_ids)
      return [] if settlement_ids.empty?

      dataset.where(settlement_id: settlement_ids).order(:created_at).all
    end

    def ids_for_settlement(settlement_id)
      DB[:settlement_transfers].where(settlement_id: settlement_id).order(:created_at).select_map(:id)
    end

    def ids_for_settlement_ids(settlement_ids)
      return {} if settlement_ids.empty?

      DB[:settlement_transfers]
        .where(settlement_id: settlement_ids)
        .order(:created_at)
        .select_map([:settlement_id, :id])
        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(settlement_id, id), h| h[settlement_id.to_s] << id.to_s }
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:settlements, id: :settlement_id)
        .join(:events, id: Sequel[:settlements][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("settlement_transfers.updated_at > ?", since))
        .select_all(:settlement_transfers)
        .all
    end

    private

    def dataset
      DB[:settlement_transfers].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        settlement_id: UUID.new(row[:settlement_id]),
        from_user_id: row[:from_user_id] ? UUID.new(row[:from_user_id]) : nil,
        to_user_id: row[:to_user_id] ? UUID.new(row[:to_user_id]) : nil,
        amount: row[:amount].to_f,
        paid_at: row[:paid_at],
        superseded_at: row[:superseded_at],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
