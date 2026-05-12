# frozen_string_literal: true

module Events
  # Fans an event_canceled notification out to every attending RSVP except
  # the actor. Recipient ids must be captured before the event row is
  # gone — RSVPs cascade-delete with the event, so the caller passes the
  # snapshot in.
  module OnCanceled
    class << self
      def call(event:, attending_user_ids:)
        Notifications::Safely.deliver(context: "Events::OnCanceled") do
          recipient_ids = attending_user_ids - [event.user_id.to_s]
          return if recipient_ids.empty?

          actor = User.find(event.user_id)
          workspace = Workspace.find(event.workspace_id)
          return unless actor && workspace

          actor_name = actor.name || actor.email.to_s
          users = User.for_ids(recipient_ids)
          workspace_url = APP_CONFIG.frontend_url.to_s

          users.each do |user|
            Notifications::Dispatch.call(
              kind: :event_canceled,
              user_id: user.id.to_s,
              workspace_id: event.workspace_id.to_s,
              data: {
                email: user.email.to_s,
                recipient_name: user.name,
                actor_name: actor_name,
                event_name: event.name,
                workspace_name: workspace.name,
                workspace_url: workspace_url
              }
            )
          end
        end
      end
    end
  end
end
