# frozen_string_literal: true

module Expenses
  # Create a mirror-image expense that offsets an existing one. Copies the
  # original's payer, dates, description, and participant factors; negates
  # the amount; links back via reverts_expense_id.
  #
  # The reverted expense remains in the ledger — the revert is a new,
  # unsettled row that participates in the next settlement/top-up. Callers
  # pass only the target expense id; no other parameters are accepted, by
  # design, so the operation has one deterministic outcome.
  module Revert
    class << self
      include Dry::Monads[:result]

      def call(expense_id:, membership:, workspace_id:)
        Expense.find_result(expense_id)
               .bind { |expense| ExpensePolicy.enforce(:revert, expense, membership: membership) }
               .bind { |expense| check_not_already_reverted(expense) }
               .bind { |expense| insert_revert(expense, membership, workspace_id) }
      end

      private

      def check_not_already_reverted(expense)
        if DB[:expenses].where(reverts_expense_id: expense.id).any?
          Failure(ServiceError.validation("This expense has already been reverted"))
        else
          Success(expense)
        end
      end

      def insert_revert(original, membership, workspace_id)
        revert_id = SecureRandom.uuid
        now = Time.now

        DB.transaction do
          DB[:expenses].insert(
            id: revert_id,
            event_id: original.event_id,
            user_id: original.user_id,
            reverts_expense_id: original.id,
            amount: -original.amount,
            description: "Reverts: #{original.description}",
            start_date: original.start_date,
            end_date: original.end_date,
            created_at: now,
            updated_at: now
          )

          ExpenseParticipant.for_expense(original.id).each do |participant|
            DB[:expense_participants].insert(
              id: SecureRandom.uuid,
              expense_id: revert_id,
              user_id: participant.user_id,
              factor: participant.factor,
              created_at: now,
              updated_at: now
            )
          end

          Broadcaster.object_changed("expense", revert_id, workspace_id: workspace_id)
          # The original's permissions change (revert becomes disallowed) so
          # clients need to refresh it too.
          Broadcaster.object_changed("expense", original.id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(membership: membership)
        revert = Expense.find(revert_id)
        pool.add(:expense, [revert, Expense.find(original.id)].compact)
        Success({ objects: pool.to_a })
      end
    end
  end
end
