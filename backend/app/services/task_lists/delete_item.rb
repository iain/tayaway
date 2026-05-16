# frozen_string_literal: true

module TaskLists
  # Service to delete a single task item.
  module DeleteItem
    class << self
      include TaskLists::Validators

      def call(task_list_id:, task_item_id:, membership:)
        Auditable.around(
          service: "TaskLists::DeleteItem",
          actor: membership,
          subject_type: "task_item",
          subject_id: task_item_id
        ) do
          Success()
            .bind { TaskList.find_result(task_list_id) }
            .bind { |task_list| TaskItem.find_result(task_item_id).fmap { |item| [task_list, item] } }
            .bind { |(task_list, item)| validate_belongs_to_list(item, task_list).fmap { [task_list, item] } }
            .bind { |(task_list, item)| TaskItemPolicy.enforce(:delete, item, membership: membership).fmap { [task_list, item] } }
            .bind { |(task_list, item)| delete_item(task_list, item) }
        end
      end

      private

      def delete_item(task_list, item)
        item_id = item.id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: task_list.workspace_id, object_type: "task_item", object_id: item_id)
          DB[:task_items].where(id: item_id).delete

          Broadcaster.object_deleted("task_item", item_id, topics: [Topic.workspace(task_list.workspace_id)])
        end

        Success({ deleted: [{ objectType: "taskItem", id: item_id.to_s }] })
      end
    end
  end
end
