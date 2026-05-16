# frozen_string_literal: true

class TaskItemSerializer
  class << self
    def serialize_batch(task_items, pool:)
      task_items.map do |item|
        {
          id: item.id.to_s,
          objectType: "taskItem",
          taskListId: item.task_list_id.to_s,
          userId: item.user_id&.to_s,
          content: item.content,
          completedAt: item.completed_at&.iso8601(3),
          position: item.position,
          createdAt: item.created_at.iso8601(3),
          updatedAt: item.updated_at.iso8601(3)
        }
      end
    end
  end
end
