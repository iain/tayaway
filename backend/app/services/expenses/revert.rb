# frozen_string_literal: true

module Expenses
  # Create a mirror-image expense that offsets an existing one. The reverted
  # expense remains in the ledger; the revert is a new unsettled row that
  # flows into the next settlement.
  module Revert
    class << self
      include Dry::Monads[:result]

      def call(expense_id:, membership:, workspace_id:)
        Expense.find_result(expense_id)
               .bind { |expense| ExpensePolicy.enforce(:revert, expense, membership: membership) }
               .bind { |expense| check_event_ready(expense) }
               .bind { |expense| insert_revert(expense, membership, workspace_id) }
      end

      private

      # The revert copies the original's dates verbatim. If the event has
      # since lost its date range the downstream math becomes unsafe.
      def check_event_ready(expense)
        event = Event.find(expense.event_id)
        if event.nil? || event.start_date.nil? || event.end_date.nil?
          Failure(ServiceError.validation("Event is missing dates — cannot revert"))
        else
          Success(expense)
        end
      end

      def insert_revert(original, membership, workspace_id)
        revert_id = SecureRandom.uuid
        now = Time.now
        failure = nil

        DB.transaction do
          # Lock the original so two concurrent revert attempts serialize; the
          # loser sees the newly-inserted sibling and exits cleanly.
          DB[:expenses].where(id: original.id).for_update.first

          if DB[:expenses].where(reverts_expense_id: original.id).any?
            failure = Failure(ServiceError.validation("This expense has already been reverted"))
            raise Sequel::Rollback
          end

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

        return failure if failure

        pool = PoolSerializer.new(membership: membership)
        revert = Expense.find(revert_id)
        return Failure(ServiceError.conflict("Revert was not persisted; retry")) if revert.nil?

        refreshed_original = Expense.find(original.id)
        pool.add(:expense, [revert, refreshed_original].compact)
        Success({ objects: pool.to_a })
      rescue Sequel::UniqueConstraintViolation
        Failure(ServiceError.validation("This expense has already been reverted"))
      rescue Sequel::ForeignKeyConstraintViolation
        Failure(ServiceError.validation("This expense was just deleted"))
      end
    end
  end
end
