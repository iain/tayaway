# typed: true
# frozen_string_literal: true

module TaskLists
  # Service to update a task item (content, completion, position, and/or list).
  module UpdateItem
    class << self
      extend T::Sig
      include Result::Methods
      include TaskLists::Validators

      sig do
        params(
          task_list_id: T.any(String, UUID),
          task_item_id: T.any(String, UUID),
          content: T.nilable(String),
          completed: T.nilable(T::Boolean),
          position: T.nilable(Float),
          new_task_list_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(task_list_id:, task_item_id:, content: nil, completed: nil, position: nil, new_task_list_id: nil)
        TaskList.find_result(task_list_id)
                .bind { |task_list| TaskItem.find_result(task_item_id).fmap { |item| [task_list, item] } }
                .bind { |(task_list, item)| validate_belongs_to_list(item, task_list).fmap { [task_list, item] } }
                .bind { |(task_list, item)| resolve_target_list(task_list, new_task_list_id).fmap { |target| [task_list, item, target] } }
                .bind { |(task_list, item, target)| update_item(task_list, item, target, content, completed, position) }
      end

      private

      sig do
        params(
          source_list: TaskList,
          new_task_list_id: T.nilable(String)
        ).returns(Result[TaskList, ServiceError])
      end
      def resolve_target_list(source_list, new_task_list_id)
        return T.cast(Success(source_list), Result[TaskList, ServiceError]) if new_task_list_id.nil?

        target = TaskList.find(new_task_list_id)
        unless target
          return T.cast(Failure(ServiceError.not_found("Target list not found")), Result[TaskList, ServiceError])
        end

        unless target.workspace_id == source_list.workspace_id
          return T.cast(Failure(ServiceError.validation("Target list is in a different workspace")), Result[TaskList, ServiceError])
        end

        T.cast(Success(target), Result[TaskList, ServiceError])
      end

      sig do
        params(
          source_list: TaskList,
          item: TaskItem,
          target_list: TaskList,
          content: T.nilable(String),
          completed: T.nilable(T::Boolean),
          position: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_item(source_list, item, target_list, content, completed, position)
        if content && content.length > 5000
          return T.cast(
            Failure(ServiceError.validation("Content is too long (maximum 5000 characters)")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
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

        updated_item = T.must(TaskItem.find(item.id))
        pool = PoolSerializer.new(workspace_id: source_list.workspace_id)
        pool.add_task_item(updated_item)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
