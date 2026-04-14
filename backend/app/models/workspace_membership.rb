# frozen_string_literal: true

# Read-only workspace membership model (join table for users <-> workspaces).
class WorkspaceMembership
  attr_reader :id, :workspace_id, :user_id, :role, :created_at, :updated_at

  def initialize(
    id:,
    workspace_id:,
    user_id:,
    role:,
    created_at:,
    updated_at:
  )
    @id = id
    @workspace_id = workspace_id
    @user_id = user_id
    @role = role
    @created_at = created_at
    @updated_at = updated_at
  end

  class << self
    def find(id)
      dataset.where(id: id).first
    end

    def for_workspace(workspace_id)
      dataset.where(workspace_id: workspace_id).order(:created_at).all
    end

    def for_user(user_id)
      dataset.where(user_id: user_id).order(:created_at).all
    end

    def changed_since(workspace_id, since)
      dataset.where(workspace_id: workspace_id).where(Sequel.lit("updated_at > ?", since)).all
    end

    def ids_for_workspace(workspace_id)
      DB[:workspace_memberships]
        .where(workspace_id: workspace_id)
        .select_map(:id)
    end

    def ids_for_workspaces(workspace_ids)
      return {} if workspace_ids.empty?

      DB[:workspace_memberships]
        .where(workspace_id: workspace_ids)
        .select(:id, :workspace_id)
        .all
        .group_by { |r| r[:workspace_id].to_s }
        .transform_values { |rows| rows.map { |r| r[:id].to_s } }
    end

    def find_by_workspace_and_user(workspace_id, user_id)
      dataset.where(workspace_id: workspace_id, user_id: user_id).first
    end

    private

    def dataset
      DB[:workspace_memberships].with_row_proc(method(:from_row))
    end

    def from_row(row)
      WorkspaceMembership.new(
        id: UUID.new(row[:id]),
        workspace_id: UUID.new(row[:workspace_id]),
        user_id: UUID.new(row[:user_id]),
        role: row[:role],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
