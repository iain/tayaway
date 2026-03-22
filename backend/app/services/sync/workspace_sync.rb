# typed: true
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

    class << self
      extend T::Sig

      sig do
        params(workspace_id: T.any(String, UUID), since: T.nilable(Time))
          .returns(T::Hash[Symbol, T.untyped])
      end
      def call(workspace_id:, since: nil)
        cutoff = T.cast(Time.now - RETENTION_PERIOD, Time)
        full = since.nil? || since < cutoff
        effective_since = full ? Time.at(0) : T.must(since)

        synced_at = Time.now
        workspace = Workspace.find(workspace_id)
        return empty_response(synced_at, full ? "full" : "partial") unless workspace

        pool = PoolSerializer.new(workspace_id: workspace_id)

        # Always include workspace so memberIds stays current on partial syncs
        # (adding a member doesn't update the workspace's updated_at)
        pool.add_workspace(workspace)

        batch_methods = {
          "Event" => :add_events_batch,
          "DatePoll" => :add_date_polls_batch,
          "DateRange" => :add_date_ranges_batch,
          "Settlement" => :add_settlements_batch,
          "WorkspaceMembership" => :add_members_batch
        }

        ObjectRegistry::TYPES.each do |entry|
          model = Object.const_get(entry.model)
          items = model.changed_since(workspace_id, effective_since)
          next if items.empty?

          batch_method = batch_methods[entry.model]
          if batch_method
            pool.send(batch_method, items)
          else
            items.each { |item| pool.send(entry.pool_method, item) }
          end
        end

        # Include all members so the frontend can resolve userId references
        pool.add_members_batch(WorkspaceMembership.for_workspace(workspace_id))

        deleted = if full
                    []
                  else
                    DB[:deleted_items]
                      .where(workspace_id: workspace_id)
                      .where(Sequel.lit("deleted_at > ?", effective_since))
                      .select(:object_type, :object_id)
                      .map { |row| { objectType: row[:object_type], id: row[:object_id].to_s } }
                  end

        {
          syncType: full ? "full" : "partial",
          syncedAt: synced_at.iso8601(3),
          objects: pool.to_a,
          deleted: deleted
        }
      end

      private

      sig { params(synced_at: Time, sync_type: String).returns(T::Hash[Symbol, T.untyped]) }
      def empty_response(synced_at, sync_type)
        {
          syncType: sync_type,
          syncedAt: synced_at.iso8601(3),
          objects: [],
          deleted: []
        }
      end
    end
  end
end
