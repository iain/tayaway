# frozen_string_literal: true

module Sync
  # Delivers a user's personal data on WebSocket handshake: every workspace
  # they belong to plus their own memberships across those workspaces. This
  # is what powers the workspace selector and lets cross-workspace events
  # (role changes, removals, workspace renames) merge into the local pool
  # regardless of which workspace the user is currently looking at.
  #
  # Workspaces and memberships are also fetched in parallel by the WS
  # handshake to drive topic subscriptions, so callers can pass them in to
  # avoid the duplicate query. Notifications are always fetched here —
  # nothing else needs them at connect time.
  #
  # @example
  #   Sync::PersonalSync.call(user_id: "uuid")
  module PersonalSync
    class << self
      # Cap on the notification backlog included in the handshake lives on
      # APP_CONFIG.personal_sync_notification_limit. The frontend derives
      # unread-per-workspace badges from these rows, so the limit needs to
      # cover the typical "what's new across all my workspaces" view but
      # doesn't need to be unbounded — older items load on demand from the
      # inbox endpoint.
      def call(user_id:, workspaces: nil, memberships: nil)
        synced_at = Time.now
        workspaces ||= Workspace.for_user(user_id)
        memberships ||= WorkspaceMembership.for_user(user_id)
        notifications = Notification.for_user(user_id, limit: APP_CONFIG.personal_sync_notification_limit)

        pool = PoolSerializer.new
        pool.add(:workspace, workspaces) if workspaces.any?
        pool.add(:member, memberships) if memberships.any?
        pool.add(:notification, notifications) if notifications.any?

        {
          syncType: "personal",
          syncedAt: synced_at.iso8601(3),
          objects: pool.to_a
        }
      end
    end
  end
end
