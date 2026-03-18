# typed: true
# frozen_string_literal: true

# Read-only TaskItem model.
class TaskItem < T::Struct
  extend T::Sig

  const :id, UUID
  const :task_list_id, UUID
  const :user_id, T.nilable(UUID)
  const :content, String
  const :completed_at, T.nilable(Time)
  const :position, Float
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "taskItem",
      taskListId: task_list_id.to_s,
      userId: user_id&.to_s,
      content: content,
      completedAt: completed_at&.iso8601(3),
      position: position,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig
    include Result::Methods
    include Findable

    sig { params(id: T.any(String, UUID)).returns(T.nilable(TaskItem)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(task_list_id: T.any(String, UUID)).returns(T::Array[TaskItem]) }
    def for_task_list(task_list_id)
      dataset.where(task_list_id: task_list_id).order(:position).all
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[TaskItem]) }
    def changed_since(workspace_id, since)
      dataset
        .join(:task_lists, id: :task_list_id)
        .where(Sequel[:task_lists][:workspace_id] => workspace_id)
        .where(Sequel.lit("task_items.updated_at > ?", since))
        .select_all(:task_items)
        .all
    end

    sig { params(task_list_id: T.any(String, UUID)).returns(Float) }
    def max_position(task_list_id)
      DB[:task_items].where(task_list_id: task_list_id).max(:position).to_f
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:task_items].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(TaskItem) }
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
