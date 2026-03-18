# typed: true
# frozen_string_literal: true

module TaskLists
  # Service to update a task list (rename and/or reposition).
  module Update
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          task_list_id: T.any(String, UUID),
          name: T.nilable(String),
          position: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(task_list_id:, name:, position: nil)
        TaskList.find_result(task_list_id)
                .bind { |task_list| validate_update(name, position).fmap { task_list } }
                .bind { |task_list| update_task_list(task_list, name, position) }
      end

      private

      sig { params(name: T.nilable(String), position: T.nilable(Float)).returns(Result[TrueClass, ServiceError]) }
      def validate_update(name, position)
        has_name = name && !name.empty?
        if !has_name && position.nil?
          T.cast(Failure(ServiceError.validation("Name or position is required")), Result[TrueClass, ServiceError])
        elsif has_name && T.must(name).length > ValidationLimits::SHORT_STRING
          T.cast(Failure(ServiceError.validation("Name is too long (maximum 255 characters)")), Result[TrueClass, ServiceError])
        else
          T.cast(Success(true), Result[TrueClass, ServiceError])
        end
      end

      sig do
        params(
          task_list: TaskList,
          name: T.nilable(String),
          position: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_task_list(task_list, name, position)
        DB.transaction do
          updates = { updated_at: Time.now }
          updates[:name] = name if name && !name.empty?
          updates[:position] = position unless position.nil?
          DB[:task_lists].where(id: task_list.id).update(updates)
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
