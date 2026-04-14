# frozen_string_literal: true

# Read-only TaskItem model.
class TaskItem
  attr_reader :id, :task_list_id, :user_id, :content, :completed_at, :position, :created_at, :updated_at

  def initialize(
    id:,
    task_list_id:,
    user_id:,
    content:,
    completed_at:,
    position:,
    created_at:,
    updated_at:
  )
    @id = id
    @task_list_id = task_list_id
    @user_id = user_id
    @content = content
    @completed_at = completed_at
    @position = position
    @created_at = created_at
    @updated_at = updated_at
  end

  class << self
    include Dry::Monads[:result]
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_task_list(task_list_id)
      dataset.where(task_list_id: task_list_id).order(:position).all
    end

    def for_task_lists(task_list_ids)
      return [] if task_list_ids.empty?

      dataset.where(task_list_id: task_list_ids).order(:task_list_id, :position).all
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:task_lists, id: :task_list_id)
        .where(Sequel[:task_lists][:workspace_id] => workspace_id)
        .where(Sequel.lit("task_items.updated_at > ?", since))
        .select_all(:task_items)
        .all
    end

    def max_position(task_list_id)
      DB[:task_items].where(task_list_id: task_list_id).max(:position).to_f
    end

    private

    def dataset
      DB[:task_items].with_row_proc(method(:from_row))
    end

    def from_row(row)
      TaskItem.new(
        id: UUID.new(row[:id]),
        task_list_id: UUID.new(row[:task_list_id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        content: row[:content],
        completed_at: row[:completed_at],
        position: row[:position].to_f,
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
