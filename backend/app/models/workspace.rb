# frozen_string_literal: true

# Read-only workspace model.
class Workspace
  attr_reader :id, :name, :created_at, :updated_at

  def initialize(
    id:,
    name:,
    created_at:,
    updated_at:
  )
    @id = id
    @name = name
    @created_at = created_at
    @updated_at = updated_at
  end

  class << self
    def find(id)
      dataset.where(id: id).first
    end

    def changed_since(workspace_id, since)
      dataset.where(id: workspace_id).where(Sequel.lit("updated_at > ?", since)).all
    end

    def for_user(user_id)
      workspace_ids = DB[:workspace_memberships]
                      .where(user_id: user_id)
                      .select(:workspace_id)
      dataset.where(id: workspace_ids).order(:name).all
    end

    private

    def dataset
      DB[:workspaces].with_row_proc(method(:from_row))
    end

    def from_row(row)
      Workspace.new(
        id: UUID.new(row[:id]),
        name: row[:name],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
