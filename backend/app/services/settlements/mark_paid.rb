# typed: true
# frozen_string_literal: true

module Settlements
  # Service to toggle paid status on a settlement transfer.
  # Only the transfer recipient (to_user) can mark/unmark a transfer as paid.
  module MarkPaid
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          transfer_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          paid: T::Boolean,
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(transfer_id:, current_user_id:, paid:, workspace_id:)
        SettlementTransfer.find_result(transfer_id)
                          .bind { |transfer| SettlementTransferPolicy.new(transfer: transfer, user_id: current_user_id.to_s).authorize!(:mark_paid, value: transfer) }
                          .bind { |transfer| update_paid(transfer, current_user_id, paid, workspace_id) }
      end

      private

      sig do
        params(
          transfer: SettlementTransfer,
          current_user_id: T.any(String, UUID),
          paid: T::Boolean,
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_paid(transfer, current_user_id, paid, workspace_id)
        paid_at = paid ? Time.now : nil

        DB[:settlement_transfers].where(id: transfer.id).update(paid_at: paid_at, updated_at: Time.now)
        Broadcaster.object_changed("settlement_transfer", transfer.id, workspace_id: workspace_id)

        updated = T.must(SettlementTransfer.find(transfer.id))
        pool = PoolSerializer.new(workspace_id: workspace_id, user_id: current_user_id.to_s)
        pool.add_settlement_transfer(updated)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
