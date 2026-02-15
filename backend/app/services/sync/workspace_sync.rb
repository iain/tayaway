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
        if since.nil? || since < cutoff
          full_sync(workspace_id)
        else
          partial_sync(workspace_id, since)
        end
      end

      private

      sig { params(workspace_id: T.any(String, UUID)).returns(T::Hash[Symbol, T.untyped]) }
      def full_sync(workspace_id)
        synced_at = Time.now
        workspace = Workspace.find(workspace_id)
        return empty_response(synced_at, "full") unless workspace

        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_workspace_with_events(workspace)

        {
          syncType: "full",
          syncedAt: synced_at.iso8601(3),
          objects: pool.to_a,
          deleted: []
        }
      end

      sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Hash[Symbol, T.untyped]) }
      def partial_sync(workspace_id, since)
        synced_at = Time.now
        pool = PoolSerializer.new(workspace_id: workspace_id)

        user_ids = Set.new

        ObjectRegistry::TYPES.each do |entry|
          model = Object.const_get(entry.model)
          items = model.changed_since(workspace_id, since)
          items.each do |item|
            pool.send(entry.pool_method, item, cascade: false)
            user_ids << item.user_id if entry.tracks_user
          end
        end

        users = User.for_ids(user_ids.map(&:to_s))
        users.each { |u| pool.add_member_from_user(u) }

        # Query deletion log
        deleted = DB[:deleted_items]
                  .where(workspace_id: workspace_id)
                  .where(Sequel.lit("deleted_at > ?", since))
                  .select(:object_type, :object_id)
                  .map { |row| { objectType: row[:object_type], id: row[:object_id].to_s } }

        {
          syncType: "partial",
          syncedAt: synced_at.iso8601(3),
          objects: pool.to_a,
          deleted: deleted
        }
      end

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
