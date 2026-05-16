# frozen_string_literal: true

module TaskLists
  # Service to delete a task list (cascades to items in DB).
  module Delete
    class << self
      def call(task_list_id:, membership:)
        Auditable.around(
          service: "TaskLists::Delete",
          actor: membership,
          subject_type: "task_list",
          subject_id: task_list_id
        ) do
          Success()
            .bind { TaskList.find_result(task_list_id) }
            .bind { |task_list| TaskListPolicy.enforce(:delete, task_list, membership: membership) }
            .bind { |task_list| delete_task_list(task_list) }
        end
      end

      private

      def delete_task_list(task_list)
        list_id = task_list.id
        workspace_id = task_list.workspace_id
        deleted = []

        DB.transaction do
          # Track and broadcast each task item before the FK cascade drops them
          # so partial-sync `deleted` payloads stay complete and live clients
          # don't have to rely on their local cascade rule alone.
          item_ids = DB[:task_items].where(task_list_id: list_id).select_map(:id)
          if item_ids.any?
            DeletedItems.bulk_insert(workspace_id, "task_item", item_ids)
            item_ids.each do |item_id|
              Broadcaster.object_deleted("task_item", item_id, topics: ["workspace:#{workspace_id}"])
              deleted << { objectType: "taskItem", id: item_id.to_s }
            end
          end

          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "task_list", object_id: list_id)
          DB[:task_lists].where(id: list_id).delete
          Broadcaster.object_deleted("task_list", list_id, topics: ["workspace:#{workspace_id}"])
          deleted << { objectType: "taskList", id: list_id.to_s }
        end

        Success({ deleted: deleted })
      end
    end
  end
end
