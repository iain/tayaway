# frozen_string_literal: true

module Expenses
  # Service to update an expense (description and/or amount). Creator-only.
  module Update
    class << self
      include Dry::Monads[:result]

      def call(expense_id:, membership:, workspace_id:, description:, amount:,
               start_date: nil, end_date: nil,
               participant_ids: nil, participants: nil)
        # Mutated inside the chain once the expense is loaded so the audit
        # row carries who the action was about, not just who did it.
        audit_context = { amount: amount }

        Auditable.around(
          service: "Expenses::Update",
          actor: membership,
          subject_type: "expense",
          subject_id: expense_id,
          workspace_id: workspace_id,
          context: audit_context
        ) do
          Success()
            .bind { Expense.find_result(expense_id) }
            .bind { |expense| Auditable.record_subject_user_id(audit_context, expense) }
            .bind { |expense| ExpensePolicy.enforce(:edit, expense, membership: membership) }
            .bind { |expense| validate_update(expense, description, amount, start_date, end_date, participants, participant_ids) }
            .bind { |valid| update_expense(valid, workspace_id, membership) }
        end
      end

      private

      def validate_update(expense, description, amount, start_date, end_date, participants, participant_ids)
        has_description = description && !description.empty?
        has_amount = !amount.nil?
        has_dates = (start_date && !start_date.empty?) || (end_date && !end_date.empty?)
        has_participants_new = !participants.nil?
        has_participants_legacy = !participant_ids.nil?
        has_any_participants = has_participants_new || has_participants_legacy

        if !has_description && !has_amount && !has_dates && !has_any_participants
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

        if has_any_participants
          if (err = Expenses::Create.send(:participants_shape_error, participants, participant_ids))
            return Failure(ServiceError.validation(err))
          end
        end

        normalized = normalize_participants(participants, participant_ids)

        if normalized && !normalized.empty?
          user_ids = normalized.map { |p| p[:user_id] }
          if user_ids.uniq.length != user_ids.length
            return Failure(ServiceError.validation("Participants must be unique"))
          end

          existing_count = DB[:users].where(id: user_ids).count
          if existing_count != user_ids.length
            return Failure(ServiceError.validation("One or more participant user IDs are invalid"))
          end

          normalized.each do |p|
            next if p[:factor].nil?
            unless Expenses::Create.send(:valid_factor?, p[:factor])
              return Failure(ServiceError.validation(Expenses::Create::FACTOR_ERROR))
            end
          end
        end

        Success(
          expense: expense,
          description: description,
          amount: amount,
          start_date: start_date,
          end_date: end_date,
          participants: has_any_participants ? (normalized || []) : nil
        )
      end

      def normalize_participants(participants, participant_ids)
        return nil if participants.nil? && participant_ids.nil?

        if participants && !participants.empty?
          participants.map do |p|
            { user_id: (p[:user_id] || p["user_id"]).to_s, factor: (p[:factor] || p["factor"] || 1.0).to_f }
          end
        elsif participants
          []
        else
          participant_ids.map { |uid| { user_id: uid.to_s, factor: nil } }
        end
      end

      def update_expense(valid, workspace_id, membership)
        expense = valid[:expense]
        DB.transaction do
          updates = { updated_at: Time.now }
          updates[:description] = valid[:description] if valid[:description] && !valid[:description].empty?
          updates[:amount] = valid[:amount] unless valid[:amount].nil?
          if valid[:start_date] && !valid[:start_date].empty? && valid[:end_date] && !valid[:end_date].empty?
            updates[:start_date] = Date.strptime(valid[:start_date], "%Y-%m-%d")
            updates[:end_date] = Date.strptime(valid[:end_date], "%Y-%m-%d")
          end
          DB[:expenses].where(id: expense.id).update(updates)

          sync_participants(expense.id, valid[:participants], workspace_id) unless valid[:participants].nil?

          Broadcaster.object_changed("expense", expense.id, workspace_id: workspace_id)
        end

        updated = Expense.find(expense.id)
        pool = PoolSerializer.new(membership: membership)
        pool.add(:expense, [updated])

        Success({ objects: pool.to_a })
      end

      def sync_participants(expense_id, participants, workspace_id)
        desired_by_user = participants.to_h { |p| [p[:user_id], p[:factor]] }
        desired_user_ids = desired_by_user.keys

        existing = ExpenseParticipant.for_expense(expense_id)
        existing_by_user = existing.to_h { |p| [p.user_id.to_s, p] }

        to_remove = existing.reject { |p| desired_user_ids.include?(p.user_id.to_s) }
        to_remove.each do |p|
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "expense_participant", object_id: p.id)
          Broadcaster.object_deleted("expense_participant", p.id, workspace_id: workspace_id)
        end
        unless to_remove.empty?
          DB[:expense_participants].where(id: to_remove.map(&:id)).delete
        end

        now = Time.now
        desired_by_user.each do |user_id, factor|
          if (existing_row = existing_by_user[user_id])
            effective_factor = factor.nil? ? existing_row.factor : factor
            if existing_row.factor != effective_factor
              DB[:expense_participants].where(id: existing_row.id).update(factor: effective_factor, updated_at: now)
              Broadcaster.object_changed("expense_participant", existing_row.id, workspace_id: workspace_id)
            end
          else
            effective_factor = factor.nil? ? 1.0 : factor
            pid = SecureRandom.uuid
            DB[:expense_participants].insert(
              id: pid,
              expense_id: expense_id,
              user_id: user_id,
              factor: effective_factor,
              created_at: now,
              updated_at: now
            )
            Broadcaster.object_changed("expense_participant", pid, workspace_id: workspace_id)
          end
        end
      end
    end
  end
end
