# frozen_string_literal: true

module Settlements
  # Service to toggle paid status on a settlement transfer.
  # Only the transfer recipient (to_user) can mark/unmark a transfer as paid.
  module MarkPaid
    class << self
      def call(transfer_id:, paid:, membership:, workspace_id:)
        Auditable.around(
          service: "Settlements::MarkPaid",
          actor: membership,
          subject_type: "settlement_transfer",
          subject_id: transfer_id,
          workspace_id: workspace_id,
          context: { paid: paid }
        ) do
          Success()
            .bind { SettlementTransfer.find_result(transfer_id) }
            .bind do |transfer|
              has_successor = Settlement.successor?(transfer.settlement_id)
              SettlementTransferPolicy.enforce(
                :mark_paid, transfer,
                membership: membership, has_successor: has_successor
              )
            end
            .bind { |transfer| update_paid(transfer, paid, workspace_id, membership) }
        end
      end

      private

      def update_paid(transfer, paid, workspace_id, membership)
        paid_at = paid ? Time.now : nil
        failure = nil
        updated = nil

        DB.transaction do
          # Take the same event-level lock Settlements::Create holds so a
          # concurrent top-up can't commit a supersede or wedge a follow-up
          # between our policy checks and the paid_at write.
          event_id = DB[:settlements].where(id: transfer.settlement_id).get(:event_id)
          DB[:events].where(id: event_id).for_update.first if event_id

          # Re-read under the lock so we can distinguish "row went away
          # because the settlement was deleted" from the policy-handled
          # state-precondition denials below.
          current = SettlementTransfer.find(transfer.id)
          if current.nil?
            failure = Failure(ServiceError.conflict("This transfer no longer exists — its settlement was deleted"))
            raise Sequel::Rollback
          end

          # Re-enforce the policy with chain state read inside the lock,
          # closing the race between the call-site enforce and us. Same
          # rules apply (superseded, locked_in_followup, recipient).
          has_successor = Settlement.successor?(current.settlement_id)
          re_enforce = SettlementTransferPolicy.enforce(
            :mark_paid, current,
            membership: membership, has_successor: has_successor
          )
          if re_enforce.failure?
            failure = re_enforce
            raise Sequel::Rollback
          end

          DB[:settlement_transfers]
            .where(id: transfer.id)
            .update(paid_at: paid_at, paid_by_user_id: paid ? membership.user_id : nil)
          Broadcaster.object_changed("settlement_transfer", transfer.id)
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
