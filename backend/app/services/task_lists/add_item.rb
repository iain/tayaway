# typed: true
# frozen_string_literal: true

module TaskLists
  # Service to add an item to a task list.
  module AddItem
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          task_list_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          content: T.nilable(String),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(task_list_id:, user_id:, content:, id: nil)
        TaskList.find_result(task_list_id)
                .bind { |task_list| validate_content(content).fmap { |valid_content| [task_list, valid_content] } }
                .bind { |(task_list, valid_content)| add_item(task_list, user_id, valid_content, id) }
      end

      private

      sig { params(content: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_content(content)
        if content.nil? || content.empty?
          T.cast(Failure(ServiceError.validation("Content is required")), Result[String, ServiceError])
        elsif content.length > 5000
          T.cast(Failure(ServiceError.validation("Content is too long (maximum 5000 characters)")), Result[String, ServiceError])
        else
          T.cast(Success(content), Result[String, ServiceError])
        end
      end

      sig do
        params(
          task_list: TaskList,
          user_id: T.any(String, UUID),
          content: String,
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def add_item(task_list, user_id, content, id)
        # Idempotent replay: if client provided an ID and it already exists, return the item
        if id
          existing = TaskItem.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: task_list.workspace_id)
            pool.add_task_item(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
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

        item = T.must(TaskItem.find(item_id))
        pool = PoolSerializer.new(workspace_id: task_list.workspace_id)
        pool.add_task_item(item)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
