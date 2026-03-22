# typed: true
# frozen_string_literal: true

module Expenses
  # Service to create a new expense on an event.
  module Create
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          description: T.nilable(String),
          amount: T.nilable(Float),
          start_date: T.nilable(String),
          end_date: T.nilable(String),
          id: T.nilable(String),
          participant_ids: T.nilable(T::Array[String])
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, user_id:, workspace_id:, description:, amount:, start_date:, end_date:, id: nil, participant_ids: nil)
        validate(description, amount, start_date, end_date)
          .bind { |valid| validate_date_range(valid, event_id) }
          .bind { |valid| validate_rsvp(valid, event_id, user_id) }
          .bind { |valid| validate_participants(valid, participant_ids) }
          .bind { |valid| create_expense(event_id, user_id, workspace_id, valid, id) }
      end

      private

      sig do
        params(
          description: T.nilable(String),
          amount: T.nilable(Float),
          start_date: T.nilable(String),
          end_date: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate(description, amount, start_date, end_date)
        if description.nil? || description.empty?
          return T.cast(
            Failure(ServiceError.validation("Description is required")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if description.length > ValidationLimits::SHORT_STRING
          return T.cast(
            Failure(ServiceError.validation("Description is too long (maximum 255 characters)")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if amount.nil? || amount <= 0
          return T.cast(
            Failure(ServiceError.validation("Amount must be greater than zero")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if amount > ValidationLimits::EXPENSE_AMOUNT_MAX
          return T.cast(
            Failure(ServiceError.validation("Amount cannot exceed 1,000,000")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if start_date.nil? || start_date.empty? || end_date.nil? || end_date.empty?
          return T.cast(
            Failure(ServiceError.validation("Start date and end date are required")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        parsed_start, parsed_end = begin
          [Date.strptime(start_date, "%Y-%m-%d"), Date.strptime(end_date, "%Y-%m-%d")]
        rescue Date::Error
          return T.cast(
            Failure(ServiceError.validation("Dates must be in YYYY-MM-DD format")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if parsed_start > parsed_end
          return T.cast(
            Failure(ServiceError.validation("Start date must be on or before end date")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        T.cast(
          Success({ description: description, amount: amount, start_date: parsed_start, end_date: parsed_end }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end

      sig do
        params(
          valid: T::Hash[Symbol, T.untyped],
          event_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate_date_range(valid, event_id)
        event = Event.find(event_id)
        if event&.start_date && event.end_date
          if valid[:start_date] < event.start_date || valid[:end_date] > event.end_date
            return T.cast(
              Failure(ServiceError.validation("Expense dates must fall within event date range")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end
        end

        T.cast(Success(valid), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          valid: T::Hash[Symbol, T.untyped],
          event_id: T.any(String, UUID),
          user_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate_rsvp(valid, event_id, user_id)
        rsvp = Rsvp.find_by_event_and_user(event_id, user_id)

        if rsvp.nil? || !rsvp.attending
          return T.cast(
            Failure(ServiceError.forbidden("You must RSVP to this event before adding expenses")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        T.cast(Success(valid), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          valid: T::Hash[Symbol, T.untyped],
          participant_ids: T.nilable(T::Array[String])
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate_participants(valid, participant_ids)
        if participant_ids.nil? || participant_ids.empty?
          valid[:participant_ids] = nil
          return T.cast(Success(valid), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end

        deduped = participant_ids.uniq

        # Verify all participant user_ids exist
        existing_count = DB[:users].where(id: deduped).count
        if existing_count != deduped.length
          return T.cast(
            Failure(ServiceError.validation("One or more participant user IDs are invalid")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        valid[:participant_ids] = deduped
        T.cast(Success(valid), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          event_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          valid: T::Hash[Symbol, T.untyped],
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_expense(event_id, user_id, workspace_id, valid, id)
        # Idempotent replay: if client provided an ID and it already exists, return it
        if id
          existing = Expense.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add_expense(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        expense = begin
          DB.transaction do
            now = Time.now
            expense_id = id || SecureRandom.uuid

            DB[:expenses].insert(
              id: expense_id,
              event_id: event_id,
              user_id: user_id,
              amount: valid[:amount],
              description: valid[:description],
              start_date: valid[:start_date],
              end_date: valid[:end_date],
              created_at: now,
              updated_at: now
            )

            insert_participants(expense_id, valid[:participant_ids], workspace_id)

            Broadcaster.object_changed("expense", expense_id, workspace_id: workspace_id)

            Expense.find(expense_id)
          end
        rescue Sequel::UniqueConstraintViolation
          T.must(Expense.find(T.must(id)))
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_expense(expense)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          expense_id: T.any(String, UUID),
          participant_ids: T.nilable(T::Array[String]),
          workspace_id: T.any(String, UUID)
        ).void
      end
      def insert_participants(expense_id, participant_ids, workspace_id)
        return if participant_ids.nil? || participant_ids.empty?

        now = Time.now
        participant_ids.each do |pid|
          participant_id = SecureRandom.uuid
          DB[:expense_participants].insert(
            id: participant_id,
            expense_id: expense_id,
            user_id: pid,
            created_at: now
          )
          Broadcaster.object_changed("expense_participant", participant_id, workspace_id: workspace_id)
        end
      end
    end
  end
end
