# frozen_string_literal: true

# Read-only TaskList model.
class TaskList
  attr_reader :id, :workspace_id, :user_id, :name, :position, :created_at, :updated_at

  def initialize(
    id:,
    workspace_id:,
    user_id:,
    name:,
    position:,
    created_at:,
    updated_at:
  )
    @id = id
    @workspace_id = workspace_id
    @user_id = user_id
    @name = name
    @position = position
    @created_at = created_at
    @updated_at = updated_at
  end

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
    include Result::Methods
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_workspace(workspace_id)
      dataset.where(workspace_id: workspace_id).order(:position).all
    end

    def changed_since(workspace_id, since)
      dataset
        .where(workspace_id: workspace_id)
        .where(Sequel.lit("updated_at > ?", since))
        .all
    end

    def max_position(workspace_id)
      DB[:task_lists].where(workspace_id: workspace_id).max(:position).to_f
    end

    private

    def dataset
      DB[:task_lists].with_row_proc(method(:from_row))
    end

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
