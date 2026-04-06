# frozen_string_literal: true

module TaskLists
  # Service to delete a task list (cascades to items in DB).
  module Delete
    class << self
      include Result::Methods

      def call(task_list_id:)
        TaskList.find_result(task_list_id)
                .bind { |task_list| delete_task_list(task_list) }
      end

      private

      def delete_task_list(task_list)
        list_id = task_list.id
        workspace_id = task_list.workspace_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "task_list", object_id: list_id)
          DB[:task_lists].where(id: list_id).delete
          Broadcaster.object_deleted("task_list", list_id, workspace_id: workspace_id)
        end

        Success({ deleted: [{ objectType: "taskList", id: list_id.to_s }] })
      end
    end
  end
end
