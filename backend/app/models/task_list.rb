# typed: true
# frozen_string_literal: true

# Read-only TaskList model.
class TaskList < T::Struct
  extend T::Sig

  const :id, UUID
  const :workspace_id, UUID
  const :user_id, T.nilable(UUID)
  const :name, String
  const :position, Float
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "taskList",
      workspaceId: workspace_id.to_s,
      userId: user_id&.to_s,
      name: name,
      position: position,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig
    include Result::Methods
    include Findable

    sig { params(id: T.any(String, UUID)).returns(T.nilable(TaskList)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(workspace_id: T.any(String, UUID)).returns(T::Array[TaskList]) }
    def for_workspace(workspace_id)
      dataset.where(workspace_id: workspace_id).order(:position).all
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[TaskList]) }
    def changed_since(workspace_id, since)
      dataset
        .where(workspace_id: workspace_id)
        .where(Sequel.lit("updated_at > ?", since))
        .all
    end

    sig { params(workspace_id: T.any(String, UUID)).returns(Float) }
    def max_position(workspace_id)
      DB[:task_lists].where(workspace_id: workspace_id).max(:position).to_f
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:task_lists].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(TaskList) }
    def from_row(row)
      TaskList.new(
        id: UUID.new(row[:id]),
        workspace_id: UUID.new(row[:workspace_id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        name: row[:name],
        position: row[:position].to_f,
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
