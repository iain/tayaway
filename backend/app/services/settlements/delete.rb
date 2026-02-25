# typed: true
# frozen_string_literal: true

module Settlements
  # Service to delete a settlement and unlock its expenses.
  # Only the settlement creator or event owner can delete.
  module Delete
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          settlement_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(settlement_id:, current_user_id:, workspace_id:)
        Settlement.find_result(settlement_id)
                  .bind { |settlement| authorize(settlement, current_user_id) }
                  .bind { |settlement| delete_settlement(settlement, workspace_id) }
      end

      private

      sig do
        params(settlement: Settlement, current_user_id: T.any(String, UUID))
          .returns(Result[Settlement, ServiceError])
      end
      def authorize(settlement, current_user_id)
        # Creator can delete
        if settlement.user_id&.to_s == current_user_id.to_s
          return T.cast(Success(settlement), Result[Settlement, ServiceError])
        end

        # Event owner can delete
        event = Event.find(settlement.event_id)
        if event && event.user_id.to_s == current_user_id.to_s
          return T.cast(Success(settlement), Result[Settlement, ServiceError])
        end

        T.cast(
          Failure(ServiceError.forbidden("Not authorized to delete this settlement")),
          Result[Settlement, ServiceError]
        )
      end

      sig do
        params(settlement: Settlement, workspace_id: T.any(String, UUID))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def delete_settlement(settlement, workspace_id)
        pool = PoolSerializer.new(workspace_id: workspace_id)
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
        Expense.for_event(settlement.event_id).each { |e| pool.add_expense(e) }

        T.cast(
          Success({ objects: pool.to_a, deleted: deleted }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end
    end
  end
end
