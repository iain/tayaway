# typed: true
# frozen_string_literal: true

module TaskLists
  # Service to rename a task list.
  module Update
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          task_list_id: T.any(String, UUID),
          name: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(task_list_id:, name:)
        TaskList.find_result(task_list_id)
                .bind { |task_list| validate_name(name).fmap { |valid_name| [task_list, valid_name] } }
                .bind { |(task_list, valid_name)| update_task_list(task_list, valid_name) }
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

      sig { params(task_list: TaskList, name: String).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def update_task_list(task_list, name)
        DB.transaction do
          DB[:task_lists].where(id: task_list.id).update(name: name, updated_at: Time.now)
          Broadcaster.object_changed("task_list", task_list.id, workspace_id: task_list.workspace_id)
        end

        updated = T.must(TaskList.find(task_list.id))
        pool = PoolSerializer.new(workspace_id: task_list.workspace_id)
        pool.add_task_list(updated)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
