# frozen_string_literal: true

module Notifications
  module Channels
    # In-app channel: writes a notification row that the recipient's
    # frontend pulls from `GET /api/notifications`. The kind is asked
    # for an `in_app_payload` so the row holds title/body/href ready
    # for display, freeing the frontend from per-kind rendering.
    module InApp
      class << self
        def deliver(kind_class:, user_id:, workspace_id:, data:)
          payload = kind_class.in_app_payload(**data)
          DB[:notifications].insert(
            id: SecureRandom.uuid,
            user_id: user_id,
            workspace_id: workspace_id,
            kind: kind_class.key.to_s,
            data: Sequel.pg_jsonb(payload)
          )
        end
      end
    end
  end
end
