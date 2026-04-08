# frozen_string_literal: true

class TaskItemPolicy
  include Policy

  ACTIONS = %i[edit delete].freeze

  def initialize(_task_item, membership:, **)
  end

  def edit
    Success()
  end

  def delete
    Success()
  end
end
