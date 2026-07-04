# frozen_string_literal: true

module TaskLists
  # Service to update a task list (rename and/or reposition).
  module Update
    class << self
      include LengthValidation

      def call(task_list_id:, name:, position: nil, membership:)
        Auditable.around(
          service: "TaskLists::Update",
          actor: membership,
          subject_type: "task_list",
          subject_id: task_list_id,
          context: { name: name }
        ) do
          Success()
            .bind { TaskList.find_result(task_list_id) }
            .bind { |task_list| TaskListPolicy.enforce(:edit, task_list, membership: membership) }
            .bind { |task_list| validate_update(name, position).fmap { task_list } }
            .bind { |task_list| update_task_list(task_list, name, position, membership) }
        end
      end

      private

      def validate_update(name, position)
        has_name = name && !name.strip.empty?
        if !has_name && position.nil?
          Failure(ServiceError.validation("Name or position is required"))
        elsif has_name
          validate_length(name, max: ValidationLimits::SHORT_STRING, field: "Name")
        else
          Success(true)
        end
      end

      def update_task_list(task_list, name, position, membership)
        DB.transaction do
          updates = { updated_at: Time.now }
          updates[:name] = name if name && !name.empty?
          updates[:position] = position unless position.nil?
          DB[:task_lists].where(id: task_list.id).update(updates)
          Broadcaster.object_changed("task_list", task_list.id)
        end

        updated = TaskList.find(task_list.id)
        pool = PoolSerializer.new(membership: membership)
        pool.add(:task_list, [updated])

        Success({ objects: pool.to_a })
      end
    end
  end
end
