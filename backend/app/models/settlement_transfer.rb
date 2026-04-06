# frozen_string_literal: true

# Read-only SettlementTransfer model.
class SettlementTransfer
  attr_reader :id, :settlement_id, :from_user_id, :to_user_id, :amount, :paid_at, :created_at, :updated_at

  def initialize(
    id:,
    settlement_id:,
    from_user_id:,
    to_user_id:,
    amount:,
    paid_at:,
    created_at:,
    updated_at:
  )
    @id = id
    @settlement_id = settlement_id
    @from_user_id = from_user_id
    @to_user_id = to_user_id
    @amount = amount
    @paid_at = paid_at
    @created_at = created_at
    @updated_at = updated_at
  end

  def to_api_hash
    {
      id: id.to_s,
      objectType: "settlementTransfer",
      settlementId: settlement_id.to_s,
      fromUserId: from_user_id&.to_s,
      toUserId: to_user_id&.to_s,
      amount: amount,
      paidAt: paid_at&.iso8601(3),
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    include Result::Methods
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_settlement(settlement_id)
      dataset.where(settlement_id: settlement_id).order(:created_at).all
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
      SettlementTransfer.new(
        id: UUID.new(row[:id]),
        settlement_id: UUID.new(row[:settlement_id]),
        from_user_id: row[:from_user_id] ? UUID.new(row[:from_user_id]) : nil,
        to_user_id: row[:to_user_id] ? UUID.new(row[:to_user_id]) : nil,
        amount: row[:amount].to_f,
        paid_at: row[:paid_at],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
