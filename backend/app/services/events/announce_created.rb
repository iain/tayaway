# frozen_string_literal: true

module Events
  # Fan an event_created notification out to every workspace member
  # except the actor. Used by both `Events::Create` (when an event lands
  # with concrete dates) and `DatePolls::Create` (when a date poll opens
  # on a still-undated event). The two callers represent the only
  # moments the event becomes worth telling people about: a fixed date,
  # or a poll asking them to weigh in. An undated, poll-less event is a
  # placeholder and stays silent until one of those things happens.
  #
  # Errors are logged and swallowed so a notification failure can't
  # block the underlying create flow.
  module AnnounceCreated
    class << self
      def call(event:, actor_user_id:)
        actor = User.find(actor_user_id)
        workspace = Workspace.find(event.workspace_id)
        return unless actor && workspace

        actor_name = actor.name || actor.email.to_s
        recipient_user_ids = WorkspaceMembership
                             .for_workspace(event.workspace_id)
                             .map { |m| m.user_id.to_s } - [actor_user_id.to_s]
        return if recipient_user_ids.empty?

        users = User.for_ids(recipient_user_ids)
        event_url = "#{ENV.fetch("FRONTEND_URL", "https://tayaway.nl")}/events/#{event.id}"

        users.each do |user|
          Notifications::Dispatch.call(
            kind: :event_created,
            user_id: user.id.to_s,
            workspace_id: event.workspace_id.to_s,
            data: {
              email: user.email.to_s,
              recipient_name: user.name,
              actor_name: actor_name,
              event_name: event.name,
              workspace_name: workspace.name,
              event_url: event_url
            }
          )
        end
      rescue StandardError => e
        APP_LOGGER.error { "[Events::AnnounceCreated] Failed to dispatch event_created: #{e.class} - #{e.message}" }
      end
    end
  end
end
