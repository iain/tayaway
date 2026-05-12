# frozen_string_literal: true

module Notifications
  # Fires a synthetic push to every subscription the user has registered.
  # Delivery is synchronous so any failure (expired subscription, push
  # service rejected the request, VAPID misconfigured) surfaces in the
  # response — the whole point of the test button is to tell the user
  # whether push is actually working, which a fire-and-forget queue path
  # can't do.
  module TestPush
    PAYLOAD = {
      title: "Test from Tayaway",
      body: "Push notifications are working on this device.",
      href: "/settings/notifications"
    }.freeze

    class << self
      def call(user_id:)
        Success()
          .bind { ensure_configured }
          .bind { fetch_subscriptions(user_id) }
          .bind { |subs| dispatch(subs) }
      end

      private

      def ensure_configured
        if Notifications::Channels::Push.configured?
          Success()
        else
          Failure(ServiceError.validation("Push isn't configured on this server."))
        end
      end

      def fetch_subscriptions(user_id)
        subs = PushSubscription.for_user(user_id)
        if subs.empty?
          Failure(ServiceError.validation("No push devices registered for this account."))
        else
          Success(subs)
        end
      end

      def dispatch(subscriptions)
        payload = JSON.generate(PAYLOAD)
        delivered = 0
        last_error = nil
        subscriptions.each do |sub|
          deliver_to_one(sub, payload)
          delivered += 1
        rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
          # The browser revoked this subscription; clean it up so the
          # next test doesn't keep tripping over a dead row.
          PushSubscription.delete_endpoint(sub.endpoint)
        rescue StandardError => e
          last_error = "#{e.class}: #{e.message}"
        end

        if delivered.positive?
          Success({ devices: delivered })
        else
          Failure(ServiceError.validation(failure_message(subscriptions.length, last_error)))
        end
      end

      def deliver_to_one(sub, payload)
        WebPush.payload_send(
          message: payload,
          endpoint: sub.endpoint,
          p256dh: sub.p256dh_key,
          auth: sub.auth_key,
          vapid: {
            subject: Config.vapid_subject,
            public_key: Config.vapid_public_key,
            private_key: Config.vapid_private_key
          }
        )
      end

      def failure_message(total, last_error)
        if last_error
          "Push delivery failed: #{last_error}"
        elsif total.positive?
          "Your push subscription was expired and has been cleaned up. Re-enable push and try again."
        else
          "No push devices registered for this account."
        end
      end
    end
  end
end
