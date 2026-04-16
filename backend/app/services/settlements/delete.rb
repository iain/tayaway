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
                  .bind { |settlement| delete_settlement(settlement, workspace_id, membership) }
      end

      private

      def delete_settlement(settlement, workspace_id, membership)
        pool = PoolSerializer.new(membership: membership)
        deleted = []

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

          # Record settlement deletion
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "settlement", object_id: settlement.id)
          Broadcaster.object_deleted("settlement", settlement.id, workspace_id: workspace_id)
          deleted << { objectType: "settlement", id: settlement.id.to_s }

          # Delete settlement (cascades to transfers)
          DB[:settlements].where(id: settlement.id).delete
        end

        # Re-fetch updated expenses for the response
        pool.add(:expense, Expense.for_event(settlement.event_id))

        Success({ objects: pool.to_a, deleted: deleted })
      end
    end
  end
end
