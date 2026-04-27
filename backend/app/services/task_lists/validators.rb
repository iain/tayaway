# frozen_string_literal: true

module TaskLists
  # Shared validators for TaskLists services.
  module Validators
    def validate_belongs_to_list(item, task_list)
      if item.task_list_id == task_list.id
        Success(item)
      else
        Failure(ServiceError.validation("Item does not belong to this list"))
      end
    end
  end
end
