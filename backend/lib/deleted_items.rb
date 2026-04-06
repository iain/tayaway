# frozen_string_literal: true

# Helper for bulk-inserting deleted_items rows.
# Standardizes the pattern used across services that soft-delete objects.
module DeletedItems
  class << self
    def bulk_insert(workspace_id, object_type, object_ids, deleted_by: nil)
      return if object_ids.empty?

      rows = object_ids.map do |oid|
        row = { workspace_id: workspace_id, object_type: object_type, object_id: oid }
        row[:deleted_by] = deleted_by if deleted_by
        row
      end
      DB[:deleted_items].multi_insert(rows)
    end
  end
end
