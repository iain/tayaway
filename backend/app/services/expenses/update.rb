# frozen_string_literal: true

module Expenses
  # Service to update an expense (description and/or amount). Creator-only.
  module Update
    class << self
      include Dry::Monads[:result]

      def call(expense_id:, membership:, workspace_id:, description:, amount:, start_date: nil, end_date: nil, participant_ids: nil)
        Expense.find_result(expense_id)
               .bind { |expense| ExpensePolicy.enforce(:edit, expense, membership: membership) }
               .bind { |expense| validate_update(expense, description, amount, start_date, end_date, participant_ids) }
               .bind { |expense| update_expense(expense, workspace_id, description, amount, start_date, end_date, participant_ids) }
      end

      private

      def validate_update(expense, description, amount, start_date, end_date, participant_ids)
        has_description = description && !description.empty?
        has_amount = !amount.nil?
        has_dates = (start_date && !start_date.empty?) || (end_date && !end_date.empty?)
        has_participants = !participant_ids.nil?

        if !has_description && !has_amount && !has_dates && !has_participants
          return Failure(ServiceError.validation("Description, amount, or dates are required"))
        end

        if has_description && description.length > ValidationLimits::SHORT_STRING
          return Failure(ServiceError.validation("Description is too long (maximum 255 characters)"))
        end

        if has_amount && amount <= 0
          return Failure(ServiceError.validation("Amount must be greater than zero"))
        end

        if has_amount && amount > ValidationLimits::EXPENSE_AMOUNT_MAX
          return Failure(ServiceError.validation("Amount cannot exceed 1,000,000"))
        end

        if has_dates
          sd = start_date && !start_date.empty? ? start_date : nil
          ed = end_date && !end_date.empty? ? end_date : nil
          unless sd && ed
            return Failure(ServiceError.validation("Both start date and end date are required"))
          end
          parsed_sd, parsed_ed = begin
            [Date.strptime(sd, "%Y-%m-%d"), Date.strptime(ed, "%Y-%m-%d")]
          rescue Date::Error
            return Failure(ServiceError.validation("Dates must be in YYYY-MM-DD format"))
          end

          if parsed_sd > parsed_ed
            return Failure(ServiceError.validation("Start date must be on or before end date"))
          end

          event = Event.find(expense.event_id)
          if event&.start_date && event.end_date
            if parsed_sd < event.start_date || parsed_ed > event.end_date
              return Failure(ServiceError.validation("Expense dates must fall within event date range"))
            end
          end
        end

        if has_participants && !participant_ids.empty?
          deduped = participant_ids.uniq
          existing_count = DB[:users].where(id: deduped).count
          if existing_count != deduped.length
            return Failure(ServiceError.validation("One or more participant user IDs are invalid"))
          end
        end

        Success(expense)
      end

      def update_expense(expense, workspace_id, description, amount, start_date, end_date, participant_ids)
        DB.transaction do
          updates = { updated_at: Time.now }
          updates[:description] = description if description && !description.empty?
          updates[:amount] = amount unless amount.nil?
          if start_date && !start_date.empty? && end_date && !end_date.empty?
            updates[:start_date] = Date.strptime(start_date, "%Y-%m-%d")
            updates[:end_date] = Date.strptime(end_date, "%Y-%m-%d")
          end
          DB[:expenses].where(id: expense.id).update(updates)

          sync_participants(expense.id, participant_ids, workspace_id) unless participant_ids.nil?

          Broadcaster.object_changed("expense", expense.id, workspace_id: workspace_id)
        end

        updated = Expense.find(expense.id)
        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_expense(updated)

        Success({ objects: pool.to_a })
      end

      def sync_participants(expense_id, participant_ids, workspace_id)
        participant_ids = participant_ids.uniq
        existing = ExpenseParticipant.user_ids_for_expense(expense_id)
        to_add = participant_ids - existing
        to_remove = existing - participant_ids

        # Remove old participants
        unless to_remove.empty?
          removed = ExpenseParticipant.for_expense(expense_id).select { |p| to_remove.include?(p.user_id.to_s) }
          removed.each do |p|
            DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "expense_participant", object_id: p.id)
            Broadcaster.object_deleted("expense_participant", p.id, workspace_id: workspace_id)
          end
          DB[:expense_participants].where(expense_id: expense_id, user_id: to_remove).delete
        end

        # Add new participants
        now = Time.now
        to_add.each do |uid|
          pid = SecureRandom.uuid
          DB[:expense_participants].insert(
            id: pid,
            expense_id: expense_id,
            user_id: uid,
            created_at: now
          )
          Broadcaster.object_changed("expense_participant", pid, workspace_id: workspace_id)
        end
      end
    end
  end
end
