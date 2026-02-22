# typed: true
# frozen_string_literal: true

module TaskLists
  # Service to update a task item (content and/or completion status).
  module UpdateItem
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          task_list_id: T.any(String, UUID),
          task_item_id: T.any(String, UUID),
          content: T.nilable(String),
          completed: T.nilable(T::Boolean)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(task_list_id:, task_item_id:, content: nil, completed: nil)
        TaskList.find_result(task_list_id)
                .bind { |task_list| TaskItem.find_result(task_item_id).fmap { |item| [task_list, item] } }
                .bind { |(task_list, item)| validate_belongs_to_list(item, task_list).fmap { [task_list, item] } }
                .bind { |(task_list, item)| update_item(task_list, item, content, completed) }
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

      sig do
        params(
          task_list: TaskList,
          item: TaskItem,
          content: T.nilable(String),
          completed: T.nilable(T::Boolean)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_item(task_list, item, content, completed)
        DB.transaction do
          now = Time.now
          updates = { updated_at: now }

          updates[:content] = content if content && !content.empty?

          unless completed.nil?
            updates[:completed_at] = completed ? now : nil
          end

          DB[:task_items].where(id: item.id).update(updates)

          # Touch the parent list's updated_at for partial sync
          DB[:task_lists].where(id: task_list.id).update(updated_at: now)

          Broadcaster.object_changed("task_list", task_list.id, workspace_id: task_list.workspace_id)
        end

        updated_list = T.must(TaskList.find(task_list.id))
        pool = PoolSerializer.new(workspace_id: task_list.workspace_id)
        pool.add_task_list(updated_list)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
