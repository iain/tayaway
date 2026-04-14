# frozen_string_literal: true

module TaskLists
  # Service to update a task item (content, completion, position, and/or list).
  module UpdateItem
    class << self
      include Dry::Monads[:result]
      include TaskLists::Validators

      def call(task_list_id:, task_item_id:, membership:, content: nil, completed: nil, position: nil, new_task_list_id: nil)
        TaskList.find_result(task_list_id)
                .bind { |task_list| TaskItem.find_result(task_item_id).fmap { |item| [task_list, item] } }
                .bind { |(task_list, item)| validate_belongs_to_list(item, task_list).fmap { [task_list, item] } }
                .bind { |(task_list, item)| TaskItemPolicy.enforce(:edit, item, membership: membership).fmap { [task_list, item] } }
                .bind { |(task_list, item)| resolve_target_list(task_list, new_task_list_id).fmap { |target| [task_list, item, target] } }
                .bind { |(task_list, item, target)| update_item(task_list, item, target, content, completed, position, membership) }
      end

      private

      def resolve_target_list(source_list, new_task_list_id)
        return Success(source_list) if new_task_list_id.nil?

        target = TaskList.find(new_task_list_id)
        unless target
          return Failure(ServiceError.not_found("Target list not found"))
        end

        unless target.workspace_id == source_list.workspace_id
          return Failure(ServiceError.validation("Target list is in a different workspace"))
        end

        Success(target)
      end

      def update_item(source_list, item, target_list, content, completed, position, membership)
        if content && content.length > ValidationLimits::LONG_TEXT
          return Failure(ServiceError.validation("Content is too long (maximum 5000 characters)"))
        end

        DB.transaction do
          now = Time.now
          updates = { updated_at: now }

          updates[:content] = content if content && !content.empty?

          unless completed.nil?
            updates[:completed_at] = completed ? now : nil
          end

          updates[:position] = position unless position.nil?
          updates[:task_list_id] = target_list.id.to_s unless target_list.id == item.task_list_id

          DB[:task_items].where(id: item.id).update(updates)

          Broadcaster.object_changed("task_item", item.id, workspace_id: source_list.workspace_id)
        end

        updated_item = TaskItem.find(item.id)
        pool = PoolSerializer.new(membership: membership)
        pool.add(:task_item, [updated_item])

        Success({ objects: pool.to_a })
      end
    end
  end
end
