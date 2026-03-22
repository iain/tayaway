# typed: true
# frozen_string_literal: true

module TaskLists
  # Service to bulk-delete all completed items from a task list.
  module ClearCompleted
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(task_list_id: T.any(String, UUID))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(task_list_id:)
        TaskList.find_result(task_list_id)
                .bind { |task_list| clear_completed(task_list) }
      end

      private

      sig { params(task_list: TaskList).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def clear_completed(task_list)
        completed_items = TaskItem.for_task_list(task_list.id).select { |i| !i.completed_at.nil? }
        deleted = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

        DB.transaction do
          unless completed_items.empty?
            ids = completed_items.map(&:id)
            DeletedItems.bulk_insert(task_list.workspace_id, "task_item", ids)
            deleted = completed_items.map { |item| { objectType: "taskItem", id: item.id.to_s } }
            DB[:task_items].where(id: ids).delete
            completed_items.each do |item|
              Broadcaster.object_deleted("task_item", item.id, workspace_id: task_list.workspace_id)
            end
          end
        end

        T.cast(Success({ deleted: deleted }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
