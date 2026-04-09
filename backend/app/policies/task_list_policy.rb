# frozen_string_literal: true

class TaskListPolicy
  include Policy

  ACTIONS = %i[edit delete create_task_item].freeze

  def initialize(_task_list, membership:, **)
  end

  def edit
    Success()
  end

  def delete
    Success()
  end

  def create_task_item
    Success()
  end
end
