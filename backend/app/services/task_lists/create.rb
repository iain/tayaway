# typed: true
# frozen_string_literal: true

module TaskLists
  # Service to create a new task list.
  module Create
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          workspace_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          name: T.nilable(String),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(workspace_id:, user_id:, name:, id: nil)
        validate_name(name)
          .bind { |valid_name| create_task_list(workspace_id, user_id, valid_name, id) }
      end

      private

      sig { params(name: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_name(name)
        if name.nil? || name.empty?
          T.cast(Failure(ServiceError.validation("Name is required")), Result[String, ServiceError])
        else
          T.cast(Success(name), Result[String, ServiceError])
        end
      end

      sig do
        params(
          workspace_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          name: String,
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_task_list(workspace_id, user_id, name, id)
        # Idempotent replay: if client provided an ID and it already exists, return it
        if id
          existing = TaskList.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add_task_list(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        task_list = DB.transaction do
          now = Time.now
          list_id = id || SecureRandom.uuid
          position = TaskList.max_position(workspace_id) + 1.0

          DB[:task_lists].insert(
            id: list_id,
            workspace_id: workspace_id,
            user_id: user_id,
            name: name,
            position: position,
            created_at: now,
            updated_at: now
          )

          Broadcaster.object_changed("task_list", list_id, workspace_id: workspace_id)

          TaskList.find(list_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_task_list(task_list)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
