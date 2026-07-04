# frozen_string_literal: true

module TaskLists
  # Service to create a new task list.
  module Create
    class << self
      include LengthValidation

      def call(workspace_id:, membership:, name:, id: nil)
        Auditable.around(
          service: "TaskLists::Create",
          actor: membership,
          subject_type: "task_list",
          subject_id: id,
          workspace_id: workspace_id,
          context: { name: name }
        ) do
          Success()
            .bind { Workspace.find_result(workspace_id) }
            .bind { |workspace| WorkspacePolicy.enforce(:create_task_list, workspace, membership: membership) }
            .bind { validate_name(name) }
            .bind { |valid_name| create_task_list(workspace_id, membership, valid_name, id) }
        end
      end

      private

      def validate_name(name)
        validate_length(name, max: ValidationLimits::SHORT_STRING, field: "Name", required: true)
      end

      def create_task_list(workspace_id, membership, name, id)
        # Idempotent replay: if client provided an ID and it already exists, return it
        if id
          existing = TaskList.find(id)
          if existing
            pool = PoolSerializer.new(membership: membership)
            pool.add(:task_list, [existing])
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

          Broadcaster.object_changed("task_list", list_id)

          TaskList.find(list_id)
        end

        pool = PoolSerializer.new(membership: membership)
        pool.add(:task_list, [task_list])

        Success({ objects: pool.to_a })
      end
    end
  end
end
