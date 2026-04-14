# frozen_string_literal: true

class TaskListSerializer
  class << self
    def serialize_batch(task_lists, pool:)
      return [] if task_lists.empty?
      raise ArgumentError, "TaskListSerializer requires a non-nil pool for child expansion" unless pool

      list_ids = task_lists.map(&:id)
      items = TaskItem.for_task_lists(list_ids)
      pool.add(:task_item, items) if items.any?

      task_lists.map do |tl|
        {
          id: tl.id.to_s,
          objectType: "taskList",
          workspaceId: tl.workspace_id.to_s,
          userId: tl.user_id&.to_s,
          name: tl.name,
          position: tl.position,
          createdAt: tl.created_at.iso8601(3),
          updatedAt: tl.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_task_list) = {}
    def policy_context_batch(_task_lists) = {}
  end
end
