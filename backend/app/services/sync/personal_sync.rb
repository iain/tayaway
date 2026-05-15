# frozen_string_literal: true

module Sync
  # Delivers a user's personal data on WebSocket handshake: every workspace
  # they belong to plus their own memberships across those workspaces. This
  # is what powers the workspace selector and lets cross-workspace events
  # (role changes, removals, workspace renames) merge into the local pool
  # regardless of which workspace the user is currently looking at.
  #
  # @example
  #   Sync::PersonalSync.call(user_id: "uuid")
  module PersonalSync
    class << self
      def call(user_id:)
        synced_at = Time.now
        workspaces = Workspace.for_user(user_id)
        memberships = WorkspaceMembership.for_user(user_id)

        pool = PoolSerializer.new
        pool.add(:workspace, workspaces) if workspaces.any?
        pool.add(:member, memberships) if memberships.any?

        {
          syncType: "personal",
          syncedAt: synced_at.iso8601(3),
          objects: pool.to_a,
          deleted: []
        }
      end
    end
  end
end
