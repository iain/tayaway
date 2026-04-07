# frozen_string_literal: true

module TaskLists
  # Service to add an item to a task list.
  module AddItem
    class << self
      include Dry::Monads[:result]

      def call(task_list_id:, user_id:, content:, id: nil)
        TaskList.find_result(task_list_id)
                .bind { |task_list| validate_content(content).fmap { |valid_content| [task_list, valid_content] } }
                .bind { |(task_list, valid_content)| add_item(task_list, user_id, valid_content, id) }
      end

      private

      def validate_content(content)
        if content.nil? || content.empty?
          Failure(ServiceError.validation("Content is required"))
        elsif content.length > ValidationLimits::LONG_TEXT
          Failure(ServiceError.validation("Content is too long (maximum 5000 characters)"))
        else
          Success(content)
        end
      end

      def add_item(task_list, user_id, content, id)
        # Idempotent replay: if client provided an ID and it already exists, return the item
        if id
          existing = TaskItem.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: task_list.workspace_id)
            pool.add_task_item(existing)
            return Success({ objects: pool.to_a })
          end
        end

        item_id = id || SecureRandom.uuid

        DB.transaction do
          now = Time.now
          position = TaskItem.max_position(task_list.id) + 1.0

          DB[:task_items].insert(
            id: item_id,
            task_list_id: task_list.id,
            user_id: user_id,
            content: content,
            position: position,
            created_at: now,
            updated_at: now
          )

          Broadcaster.object_changed("task_item", item_id, workspace_id: task_list.workspace_id)
        end

        item = TaskItem.find(item_id)
        pool = PoolSerializer.new(workspace_id: task_list.workspace_id)
        pool.add_task_item(item)

        Success({ objects: pool.to_a })
      end
    end
  end
end
