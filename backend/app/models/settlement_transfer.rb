# typed: true
# frozen_string_literal: true

# Read-only SettlementTransfer model.
class SettlementTransfer < T::Struct
  extend T::Sig

  const :id, UUID
  const :settlement_id, UUID
  const :from_user_id, T.nilable(UUID)
  const :to_user_id, T.nilable(UUID)
  const :amount, Float
  const :paid_at, T.nilable(Time)
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
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
    extend T::Sig
    include Result::Methods

    sig { params(id: T.any(String, UUID)).returns(T.nilable(SettlementTransfer)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(settlement_id: T.any(String, UUID)).returns(T::Array[SettlementTransfer]) }
    def for_settlement(settlement_id)
      dataset.where(settlement_id: settlement_id).order(:created_at).all
    end

    sig { params(settlement_id: T.any(String, UUID)).returns(T::Array[String]) }
    def ids_for_settlement(settlement_id)
      DB[:settlement_transfers].where(settlement_id: settlement_id).order(:created_at).select_map(:id)
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[SettlementTransfer]) }
    def changed_since(workspace_id, since)
      dataset
        .join(:settlements, id: :settlement_id)
        .join(:events, id: Sequel[:settlements][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("settlement_transfers.updated_at > ?", since))
        .select_all(:settlement_transfers)
        .all
    end

    sig { params(id: T.any(String, UUID)).returns(Result[SettlementTransfer, ServiceError]) }
    def find_result(id)
      transfer = find(id)
      if transfer
        T.cast(Success(transfer), Result[SettlementTransfer, ServiceError])
      elsif DB[:deleted_items].where(object_type: "settlement_transfer", object_id: id).first
        T.cast(Failure(ServiceError.gone("Settlement transfer not found")), Result[SettlementTransfer, ServiceError])
      else
        T.cast(Failure(ServiceError.not_found("Settlement transfer not found")), Result[SettlementTransfer, ServiceError])
      end
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:settlement_transfers].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(SettlementTransfer) }
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
