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
        failure = nil
        updated = nil

        DB.transaction do
          # Take the same event-level lock Settlements::Create holds so a
          # concurrent top-up can't commit a supersede between our
          # superseded_at check and our paid_at write (nor compute its
          # balance math against a paid_at value that we're about to change).
          event_id = DB[:settlements].where(id: transfer.settlement_id).get(:event_id)
          DB[:events].where(id: event_id).for_update.first if event_id

          # Re-read under the lock so we can distinguish between "row went
          # away because the settlement was deleted" and "row was superseded
          # by a top-up", and so the successor check below sees a consistent
          # view of the chain.
          current = SettlementTransfer.find(transfer.id)
          if current.nil?
            failure = Failure(ServiceError.conflict("This transfer no longer exists — its settlement was deleted"))
            raise Sequel::Rollback
          end
          if current.superseded_at
            failure = Failure(ServiceError.conflict("This transfer was superseded by a newer settlement"))
            raise Sequel::Rollback
          end
          # Once a follow-up settlement has been issued, its balance math
          # was computed treating this transfer as paid. Flipping it back
          # to unpaid would silently desync the chain — block it and tell
          # the user to delete the follow-up first if they really meant it.
          if !paid && Settlement.successor?(transfer.settlement_id)
            failure = Failure(ServiceError.conflict(
                                "This payment is locked in by a follow-up settlement — delete the follow-up first to unmark it"
                              )
                             )
            raise Sequel::Rollback
          end

          DB[:settlement_transfers].where(id: transfer.id).update(paid_at: paid_at)
          Broadcaster.object_changed("settlement_transfer", transfer.id, workspace_id: workspace_id)
          updated = SettlementTransfer.find(transfer.id)
        end

        return failure if failure

        pool = PoolSerializer.new(membership: membership)
        pool.add(:settlement_transfer, [updated])

        Success({ objects: pool.to_a })
      end
    end
  end
end
