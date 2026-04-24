# frozen_string_literal: true

module Settlements
  # Service to delete a settlement and unlock its expenses.
  # Only the settlement creator or event owner can delete.
  module Delete
    class << self
      include Dry::Monads[:result]

      def call(settlement_id:, membership:, workspace_id:)
        Settlement.find_result(settlement_id)
                  .bind { |settlement| SettlementPolicy.enforce(:delete, settlement, membership: membership) }
                  .bind { |settlement| check_tip(settlement) }
                  .bind { |settlement| delete_settlement(settlement, workspace_id, membership) }
      end

      private

      # Only the tip of the chain can be deleted. Mid-chain delete would
      # orphan the superseded transfers that only the successor's deletion
      # is allowed to restore.
      def check_tip(settlement)
        if Settlement.successor?(settlement.id)
          Failure(ServiceError.validation("Delete the most recent settlement first"))
        else
          Success(settlement)
        end
      end

      def delete_settlement(settlement, workspace_id, membership)
        pool = PoolSerializer.new(membership: membership)
        deleted = []
        restored_ids = []

        DB.transaction do
          # Clear settlement_id on tagged expenses and broadcast each
          expense_ids = DB[:expenses].where(settlement_id: settlement.id).select_map(:id)
          if expense_ids.any?
            DB[:expenses].where(id: expense_ids).update(settlement_id: nil, updated_at: Time.now)
            expense_ids.each do |eid|
              Broadcaster.object_changed("expense", eid, workspace_id: workspace_id)
            end
          end

          # Record transfer deletions
          transfer_ids = DB[:settlement_transfers].where(settlement_id: settlement.id).select_map(:id)
          transfer_ids.each do |tid|
            DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "settlement_transfer", object_id: tid)
            Broadcaster.object_deleted("settlement_transfer", tid, workspace_id: workspace_id)
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
          Broadcaster.object_deleted("settlement", settlement.id, workspace_id: workspace_id)
          deleted << { objectType: "settlement", id: settlement.id.to_s }

          # Delete settlement (cascades to transfers)
          DB[:settlements].where(id: settlement.id).delete

          restored_ids.each do |tid|
            Broadcaster.object_changed("settlement_transfer", tid, workspace_id: workspace_id)
          end

          # The predecessor's permissions.delete flipped from false to true
          # now that its successor is gone — clients need the fresh payload
          # to surface the delete affordance again.
          if settlement.previous_settlement_id
            Broadcaster.object_changed("settlement", settlement.previous_settlement_id, workspace_id: workspace_id)
          end
        end

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
