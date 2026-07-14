# frozen_string_literal: true

# Read-only guest model: a workspace-scoped identity for non-members brought
# along by a member (doc/attendances.md). Placeholder guests were synthesized
# by the rsvp plus-ones backfill and stay hidden from pickers until renamed.
class Guest < Data.define(:id, :workspace_id, :name, :placeholder, :created_by_user_id, :created_at, :updated_at)
  class << self
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_workspace(workspace_id)
      dataset.where(workspace_id: workspace_id).order(:name).all
    end

    def changed_since(workspace_id, since)
      dataset
        .where(workspace_id: workspace_id)
        .where(Sequel.lit("updated_at > ?", since))
        .all
    end

    private

    def dataset
      DB[:guests].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        workspace_id: UUID.new(row[:workspace_id]),
        name: row[:name],
        placeholder: row[:placeholder],
        created_by_user_id: row[:created_by_user_id] ? UUID.new(row[:created_by_user_id]) : nil,
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
