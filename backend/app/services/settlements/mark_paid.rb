# frozen_string_literal: true

module Settlements
  # Service to toggle paid status on a settlement transfer.
  # Only the transfer recipient (to_user) can mark/unmark a transfer as paid.
  module MarkPaid
    class << self
      include Dry::Monads[:result]

      def call(transfer_id:, paid:, membership:, workspace_id:)
        SettlementTransfer.find_result(transfer_id)
                          .bind { |transfer| SettlementTransferPolicy.enforce(:mark_paid, transfer, membership: membership) }
                          .bind { |transfer| update_paid(transfer, paid, workspace_id, membership) }
      end

      private

      def update_paid(transfer, paid, workspace_id, membership)
        paid_at = paid ? Time.now : nil

        # A concurrent top-up may have superseded this transfer between the
        # policy check and the update. Filtering on superseded_at prevents
        # the toggle from silently landing on a stale row; we surface a
        # conflict so the client can refresh.
        rows_affected = DB[:settlement_transfers]
                        .where(id: transfer.id, superseded_at: nil)
                        .update(paid_at: paid_at)
        if rows_affected.zero?
          return Failure(ServiceError.conflict("This transfer was superseded by a newer settlement"))
        end

        Broadcaster.object_changed("settlement_transfer", transfer.id, workspace_id: workspace_id)

        updated = SettlementTransfer.find(transfer.id)
        pool = PoolSerializer.new(membership: membership)
        pool.add(:settlement_transfer, [updated])

        Success({ objects: pool.to_a })
      end
    end
  end
end
