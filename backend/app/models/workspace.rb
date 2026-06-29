# frozen_string_literal: true

# Read-only workspace model.
class Workspace < Data.define(:id, :name, :timezone, :created_at, :updated_at)
  class << self
    include Findable

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
      new(
        id: UUID.new(row[:id]),
        name: row[:name],
        timezone: row[:timezone],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
