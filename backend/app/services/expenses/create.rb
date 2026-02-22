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
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, user_id:, workspace_id:, description:, amount:, id: nil)
        validate(description, amount)
          .bind { |valid| create_expense(event_id, user_id, workspace_id, valid[:description], valid[:amount], id) }
      end

      private

      sig do
        params(description: T.nilable(String), amount: T.nilable(Float))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate(description, amount)
        if description.nil? || description.empty?
          return T.cast(
            Failure(ServiceError.validation("Description is required")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if amount.nil? || amount <= 0
          return T.cast(
            Failure(ServiceError.validation("Amount must be greater than zero")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        T.cast(
          Success({ description: description, amount: amount }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end

      sig do
        params(
          event_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          description: String,
          amount: Float,
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_expense(event_id, user_id, workspace_id, description, amount, id)
        # Idempotent replay: if client provided an ID and it already exists, return it
        if id
          existing = Expense.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add_expense(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        expense = DB.transaction do
          now = Time.now
          expense_id = id || SecureRandom.uuid

          DB[:expenses].insert(
            id: expense_id,
            event_id: event_id,
            user_id: user_id,
            amount: amount,
            description: description,
            created_at: now,
            updated_at: now
          )

          Broadcaster.object_changed("expense", expense_id, workspace_id: workspace_id)

          Expense.find(expense_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_expense(expense)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
