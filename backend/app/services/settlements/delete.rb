# frozen_string_literal: true

module Settlements
  # Service to delete a settlement and unlock its expenses.
  # Only the settlement creator or event owner can delete.
  module Delete
    class << self
      def call(settlement_id:, membership:, workspace_id:)
        Auditable.around(
          service: "Settlements::Delete",
          actor: membership,
          subject_type: "settlement",
          subject_id: settlement_id,
          workspace_id: workspace_id
        ) do
          Success()
            .bind { Settlement.find_result(settlement_id) }
            .bind do |settlement|
              has_successor = Settlement.successor?(settlement.id)
              SettlementPolicy.enforce(
                :delete, settlement,
                membership: membership, has_successor: has_successor
              )
            end
            .bind { |settlement| delete_settlement(settlement, workspace_id, membership) }
        end
      end

      private

      def delete_settlement(settlement, workspace_id, membership)
        pool = PoolSerializer.new(membership: membership)
        deleted = []
        restored_ids = []
        failure = nil

        DB.transaction do
          # Event-level lock serializes delete against concurrent Create and
          # MarkPaid calls on the same event. Without it, a successor could
          # land between the tip check and the actual delete (the DB FK
          # would catch it, but the user would see a raw constraint error
          # instead of a clean race message).
          DB[:events].where(id: settlement.event_id).for_update.first

          # Re-enforce the policy with chain state read inside the lock so
          # a race-window successor (created between the call-site enforce
          # and now) is caught with the same `:not_tip` denial.
          has_successor = Settlement.successor?(settlement.id)
          re_enforce = SettlementPolicy.enforce(
            :delete, settlement,
            membership: membership, has_successor: has_successor
          )
          if re_enforce.failure?
            failure = re_enforce
            raise Sequel::Rollback
          end

          # Clear settlement_id on tagged expenses and broadcast each
          expense_ids = DB[:expenses].where(settlement_id: settlement.id).select_map(:id)
          if expense_ids.any?
            DB[:expenses].where(id: expense_ids).update(settlement_id: nil, updated_at: Time.now)
            expense_ids.each do |eid|
              Broadcaster.object_changed("expense", eid)
            end
          end

          # Record transfer deletions
          transfer_ids = DB[:settlement_transfers].where(settlement_id: settlement.id).select_map(:id)
          transfer_ids.each do |tid|
            DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "settlement_transfer", object_id: tid)
            Broadcaster.object_deleted("settlement_transfer", tid, topics: [Topic.workspace(workspace_id)])
            deleted << { objectType: "settlementTransfer", id: tid.to_s }
          end

          # Un-supersede the predecessor's transfers — this tip is what
          # superseded them, so deleting it must bring them back as active
          # obligations.
          if settlement.previous_settlement_id
            restored_ids = DB[:settlement_transfers]
                           .where(settlement_id: settlement.previous_settlement_id)
                           .exclude(superseded_at: nil)
                           .select_map(:id)
            if restored_ids.any?
              DB[:settlement_transfers]
                .where(id: restored_ids)
                .update(superseded_at: nil, updated_at: Time.now)
            end
          end

          # Record settlement deletion
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "settlement", object_id: settlement.id)
          Broadcaster.object_deleted("settlement", settlement.id, topics: [Topic.workspace(workspace_id)])
          deleted << { objectType: "settlement", id: settlement.id.to_s }

          # Delete settlement (cascades to transfers)
          DB[:settlements].where(id: settlement.id).delete

          restored_ids.each do |tid|
            Broadcaster.object_changed("settlement_transfer", tid)
          end

          # The predecessor's permissions.delete flipped from false to true
          # now that its successor is gone — clients need the fresh payload
          # to surface the delete affordance again.
          if settlement.previous_settlement_id
            Broadcaster.object_changed("settlement", settlement.previous_settlement_id)
          end
        end

        return failure if failure

        # Re-fetch updated expenses for the response
        pool.add(:expense, Expense.for_event(settlement.event_id))
        if restored_ids.any?
          pool.add(:settlement_transfer, restored_ids.filter_map { |tid| SettlementTransfer.find(tid) })
        end
        if settlement.previous_settlement_id
          predecessor = Settlement.find(settlement.previous_settlement_id)
          pool.add(:settlement, [predecessor]) if predecessor
        end

        Success({ objects: pool.to_a, deleted: deleted })
      end
    end
  end
end
