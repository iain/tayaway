# typed: true
# frozen_string_literal: true

module TaskLists
  # Shared validators for TaskLists services.
  module Validators
    extend T::Sig
    include Result::Methods

    sig { params(item: TaskItem, task_list: TaskList).returns(Result[TaskItem, ServiceError]) }
    def validate_belongs_to_list(item, task_list)
      if item.task_list_id == task_list.id
        T.cast(Success(item), Result[TaskItem, ServiceError])
      else
        T.cast(Failure(ServiceError.validation("Item does not belong to this list")), Result[TaskItem, ServiceError])
      end
    end
  end
end
