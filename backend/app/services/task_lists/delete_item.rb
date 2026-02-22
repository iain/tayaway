# typed: true
# frozen_string_literal: true

module TaskLists
  # Service to delete a single task item.
  module DeleteItem
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          task_list_id: T.any(String, UUID),
          task_item_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(task_list_id:, task_item_id:)
        TaskList.find_result(task_list_id)
                .bind { |task_list| TaskItem.find_result(task_item_id).fmap { |item| [task_list, item] } }
                .bind { |(task_list, item)| validate_belongs_to_list(item, task_list).fmap { [task_list, item] } }
                .bind { |(task_list, item)| delete_item(task_list, item) }
      end

      private

      sig { params(item: TaskItem, task_list: TaskList).returns(Result[TaskItem, ServiceError]) }
      def validate_belongs_to_list(item, task_list)
        if item.task_list_id == task_list.id
          T.cast(Success(item), Result[TaskItem, ServiceError])
        else
          T.cast(Failure(ServiceError.validation("Item does not belong to this list")), Result[TaskItem, ServiceError])
        end
      end

      sig { params(task_list: TaskList, item: TaskItem).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def delete_item(task_list, item)
        item_id = item.id

        DB.transaction do
          now = Time.now
          DB[:deleted_items].insert(workspace_id: task_list.workspace_id, object_type: "task_item", object_id: item_id)
          DB[:task_items].where(id: item_id).delete

          # Touch the parent list's updated_at for partial sync
          DB[:task_lists].where(id: task_list.id).update(updated_at: now)

          Broadcaster.object_changed("task_list", task_list.id, workspace_id: task_list.workspace_id)
        end

        T.cast(
          Success({ deleted: [{ objectType: "taskItem", id: item_id.to_s }] }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end
    end
  end
end
