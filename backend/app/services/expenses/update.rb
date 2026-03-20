# typed: true
# frozen_string_literal: true

module Expenses
  # Service to update an expense (description and/or amount). Creator-only.
  module Update
    class << self
      extend T::Sig
      include Result::Methods
      include Expenses::Validators

      sig do
        params(
          expense_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          description: T.nilable(String),
          amount: T.nilable(Float),
          start_date: T.nilable(String),
          end_date: T.nilable(String),
          participant_ids: T.nilable(T::Array[String])
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(expense_id:, current_user_id:, workspace_id:, description:, amount:, start_date: nil, end_date: nil, participant_ids: nil)
        Expense.find_result(expense_id)
               .bind { |expense| check_not_settled(expense) }
               .bind { |expense| check_owner(expense, current_user_id) }
               .bind { |expense| validate_update(expense, description, amount, start_date, end_date, participant_ids) }
               .bind { |expense| update_expense(expense, workspace_id, description, amount, start_date, end_date, participant_ids) }
      end

      private

      sig do
        params(
          expense: Expense,
          description: T.nilable(String),
          amount: T.nilable(Float),
          start_date: T.nilable(String),
          end_date: T.nilable(String),
          participant_ids: T.nilable(T::Array[String])
        ).returns(Result[Expense, ServiceError])
      end
      def validate_update(expense, description, amount, start_date, end_date, participant_ids)
        has_description = description && !description.empty?
        has_amount = !amount.nil?
        has_dates = (start_date && !start_date.empty?) || (end_date && !end_date.empty?)
        has_participants = !participant_ids.nil?

        if !has_description && !has_amount && !has_dates && !has_participants
          return T.cast(
            Failure(ServiceError.validation("Description, amount, or dates are required")),
            Result[Expense, ServiceError]
          )
        end

        if has_description && T.must(description).length > ValidationLimits::SHORT_STRING
          return T.cast(
            Failure(ServiceError.validation("Description is too long (maximum 255 characters)")),
            Result[Expense, ServiceError]
          )
        end

        if has_amount && T.must(amount) <= 0
          return T.cast(
            Failure(ServiceError.validation("Amount must be greater than zero")),
            Result[Expense, ServiceError]
          )
        end

        if has_amount && T.must(amount) > ValidationLimits::EXPENSE_AMOUNT_MAX
          return T.cast(
            Failure(ServiceError.validation("Amount cannot exceed 1,000,000")),
            Result[Expense, ServiceError]
          )
        end

        if has_dates
          sd = start_date && !start_date.empty? ? start_date : nil
          ed = end_date && !end_date.empty? ? end_date : nil
          unless sd && ed
            return T.cast(
              Failure(ServiceError.validation("Both start date and end date are required")),
              Result[Expense, ServiceError]
            )
          end
          parsed_sd = Date.parse(sd)
          parsed_ed = Date.parse(ed)

          if parsed_sd > parsed_ed
            return T.cast(
              Failure(ServiceError.validation("Start date must be on or before end date")),
              Result[Expense, ServiceError]
            )
          end

          event = Event.find(expense.event_id)
          if event&.start_date && event.end_date
            if parsed_sd < event.start_date || parsed_ed > event.end_date
              return T.cast(
                Failure(ServiceError.validation("Expense dates must fall within event date range")),
                Result[Expense, ServiceError]
              )
            end
          end
        end

        T.cast(Success(expense), Result[Expense, ServiceError])
      end

      sig do
        params(
          expense: Expense,
          workspace_id: T.any(String, UUID),
          description: T.nilable(String),
          amount: T.nilable(Float),
          start_date: T.nilable(String),
          end_date: T.nilable(String),
          participant_ids: T.nilable(T::Array[String])
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_expense(expense, workspace_id, description, amount, start_date, end_date, participant_ids)
        DB.transaction do
          updates = { updated_at: Time.now }
          updates[:description] = description if description && !description.empty?
          updates[:amount] = amount unless amount.nil?
          if start_date && !start_date.empty? && end_date && !end_date.empty?
            updates[:start_date] = Date.parse(start_date)
            updates[:end_date] = Date.parse(end_date)
          end
          DB[:expenses].where(id: expense.id).update(updates)

          sync_participants(expense.id, participant_ids, workspace_id) unless participant_ids.nil?

          Broadcaster.object_changed("expense", expense.id, workspace_id: workspace_id)
        end

        updated = T.must(Expense.find(expense.id))
        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_expense(updated)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          expense_id: UUID,
          participant_ids: T::Array[String],
          workspace_id: T.any(String, UUID)
        ).void
      end
      def sync_participants(expense_id, participant_ids, workspace_id)
        existing = ExpenseParticipant.user_ids_for_expense(expense_id)
        to_add = participant_ids - existing
        to_remove = existing - participant_ids

        # Remove old participants
        unless to_remove.empty?
          removed = ExpenseParticipant.for_expense(expense_id).select { |p| to_remove.include?(p.user_id.to_s) }
          removed.each do |p|
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
