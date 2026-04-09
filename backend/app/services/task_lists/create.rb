# frozen_string_literal: true

module TaskLists
  # Service to create a new task list.
  module Create
    class << self
      include Dry::Monads[:result]

      def call(workspace_id:, membership:, name:, id: nil)
        workspace = Workspace.find(workspace_id)
        WorkspacePolicy.enforce(:create_task_list, workspace, membership: membership)
                       .bind { validate_name(name) }
                       .bind { |valid_name| create_task_list(workspace_id, membership, valid_name, id) }
      end

      private

      def validate_name(name)
        if name.nil? || name.empty?
          Failure(ServiceError.validation("Name is required"))
        elsif name.length > ValidationLimits::SHORT_STRING
          Failure(ServiceError.validation("Name is too long (maximum 255 characters)"))
        else
          Success(name)
        end
      end

      def create_task_list(workspace_id, membership, name, id)
        # Idempotent replay: if client provided an ID and it already exists, return it
        if id
          existing = TaskList.find(id)
          if existing
            pool = PoolSerializer.new(membership: membership)
            pool.add_task_list(existing)
            return Success({ objects: pool.to_a })
          end
        end

        task_list = DB.transaction do
          now = Time.now
          list_id = id || SecureRandom.uuid
          position = TaskList.max_position(workspace_id) + 1.0

          DB[:task_lists].insert(
            id: list_id,
            workspace_id: workspace_id,
            user_id: membership.user_id,
            name: name,
            position: position,
            created_at: now,
            updated_at: now
          )

          Broadcaster.object_changed("task_list", list_id, workspace_id: workspace_id)

          TaskList.find(list_id)
        end

        pool = PoolSerializer.new(membership: membership)
        pool.add_task_list(task_list)

        Success({ objects: pool.to_a })
      end
    end
  end
end
