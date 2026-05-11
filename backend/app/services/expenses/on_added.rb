# frozen_string_literal: true

module Expenses
  # Fans an expense_added notification out to attending RSVPs except the
  # actor. The handler does its own RSVP/user lookups so the caller only
  # needs to hand over the freshly-created expense and the actor.
  module OnAdded
    class << self
      def call(event_id:, actor_user_id:, description:, amount:, workspace_id:)
        Notifications::Safely.deliver(context: "Expenses::OnAdded") do
          event = Event.find(event_id)
          return unless event

          recipient_ids = Rsvp.for_event(event_id)
                              .select(&:attending)
                              .map { |r| r.user_id.to_s } - [actor_user_id.to_s]
          return if recipient_ids.empty?

          users = User.for_ids(recipient_ids)
          actor = User.find(actor_user_id)
          actor_name = actor&.name || actor&.email&.to_s || "Someone"
          event_url = "#{ENV.fetch("FRONTEND_URL", "https://tayaway.nl")}/events/#{event_id}"

          users.each do |user|
            Notifications::Dispatch.call(
              kind: :expense_added,
              user_id: user.id.to_s,
              workspace_id: workspace_id.to_s,
              data: {
                email: user.email.to_s,
                recipient_name: user.name,
                actor_name: actor_name,
                description: description,
                amount: amount.to_f,
                event_name: event.name,
                event_url: event_url
              }
            )
          end
        end
      end
    end
  end
end
