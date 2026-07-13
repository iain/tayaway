# frozen_string_literal: true

module Sync
  # Service to synchronize workspace data. Supports full sync (all objects) and
  # partial sync (only objects changed since a given timestamp).
  #
  # @example Full sync
  #   Sync::WorkspaceSync.call(workspace_id: "uuid")
  #
  # @example Partial sync
  #   Sync::WorkspaceSync.call(workspace_id: "uuid", since: Time.now - 60)
  module WorkspaceSync
    RETENTION_PERIOD = 7 * 24 * 60 * 60 # 7 days in seconds
    # Rows are stamped with updated_at before COMMIT makes them visible, so a
    # change can carry a timestamp older than a cursor the client already
    # holds. Reaching back past `since` by this margin resends the recent
    # past instead of losing such rows; the client merges duplicates
    # idempotently (newer updatedAt wins, deletes are replayable).
    OVERLAP = 60 # seconds

    class << self
      def call(workspace_id:, since: nil, membership: nil)
        cutoff = Time.now - RETENTION_PERIOD
        overlapped_since = since && (since - OVERLAP)
        full = overlapped_since.nil? || overlapped_since < cutoff
        effective_since = full ? Time.at(0) : overlapped_since

        synced_at = Time.now
        workspace = Workspace.find(workspace_id)
        return empty_response(workspace_id, synced_at, full ? "full" : "partial") unless workspace

        pool = if membership
                 PoolSerializer.new(membership: membership)
               else
                 PoolSerializer.new(workspace_id: workspace_id)
               end

        # Always include workspace so memberIds stays current on partial syncs
        # (adding a member doesn't update the workspace's updated_at)
        pool.add(:workspace, [workspace])

        ObjectRegistry::TYPES.each do |entry|
          next if entry.key == "workspace" # already added
          next if entry.key == "member"    # added below with all memberships
          next unless entry.workspace_audience? # user-audience types ride their own delivery path

          model = Object.const_get(entry.model)
          items = model.changed_since(workspace_id, effective_since)
          pool.add(entry.key, items) if items.any?
        end

        # Include all members so the frontend can resolve userId references
        pool.add(:member, WorkspaceMembership.for_workspace(workspace_id))

        deleted = if full
                    []
                  else
                    # Tombstones store the registry key (snake_case); the client
                    # pool only knows client types (camelCase) and silently
                    # drops deletions for types it can't resolve — map before
                    # shipping, like the delete broadcast path does.
                    DB[:deleted_items]
                      .where(workspace_id: workspace_id)
                      .where(Sequel.lit("deleted_at > ?", effective_since))
                      .select(:object_type, :object_id)
                      .map do |row|
                        entry = ObjectRegistry::BY_KEY[row[:object_type]]
                        { objectType: entry ? entry.client_type : row[:object_type], id: row[:object_id].to_s }
                      end
                  end

        {
          syncType: full ? "full" : "partial",
          syncedAt: synced_at.iso8601(3),
          workspaceId: workspace_id.to_s,
          objects: pool.to_a,
          deleted: deleted
        }
      end

      private

      def empty_response(workspace_id, synced_at, sync_type)
        {
          syncType: sync_type,
          syncedAt: synced_at.iso8601(3),
          workspaceId: workspace_id.to_s,
          objects: [],
          deleted: []
        }
      end
    end
  end
end
