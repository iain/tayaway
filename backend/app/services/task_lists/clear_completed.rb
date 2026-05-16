# frozen_string_literal: true

module TaskLists
  # Service to bulk-delete all completed items from a task list.
  module ClearCompleted
    class << self
      def call(task_list_id:, membership:)
        Auditable.around(
          service: "TaskLists::ClearCompleted",
          actor: membership,
          subject_type: "task_list",
          subject_id: task_list_id
        ) do
          Success()
            .bind { TaskList.find_result(task_list_id) }
            .bind { |task_list| TaskListPolicy.enforce(:edit, task_list, membership: membership) }
            .bind { |task_list| clear_completed(task_list) }
        end
      end

      private

      def clear_completed(task_list)
        completed_items = TaskItem.for_task_list(task_list.id).select { |i| !i.completed_at.nil? }
        deleted = []

        DB.transaction do
          unless completed_items.empty?
            ids = completed_items.map(&:id)
            DeletedItems.bulk_insert(task_list.workspace_id, "task_item", ids)
            deleted = completed_items.map { |item| { objectType: "taskItem", id: item.id.to_s } }
            DB[:task_items].where(id: ids).delete
            completed_items.each do |item|
              Broadcaster.object_deleted("task_item", item.id, topics: ["workspace:#{task_list.workspace_id}"])
            end
          end
        end

        Success({ deleted: deleted })
      end
    end
  end
end
