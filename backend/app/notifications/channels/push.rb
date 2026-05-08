# frozen_string_literal: true

require "webpush"

module Notifications
  module Channels
    # Web push channel: sends a JSON message to every browser subscription
    # the user has registered, via VAPID-signed Web Push. Each delivery
    # runs in its own job so a single dead endpoint doesn't block the
    # others, and the worker's retry/dead-letter machinery applies to
    # each subscription independently.
    #
    # VAPID keys come from `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`
    # env vars; missing keys mean "push is not configured" and the
    # channel quietly no-ops so the rest of the dispatch (email,
    # in-app) still fires. Use `bundle exec rake notifications:vapid`
    # to generate a fresh keypair.
    module Push
      class << self
        def deliver_later(kind_class:, user_id:, data:)
          return unless configured?

          payload = kind_class.respond_to?(:push_payload) ? kind_class.push_payload(**data) : kind_class.in_app_payload(**data)
          subscriptions = PushSubscription.for_user(user_id)
          subscriptions.each do |subscription|
            DeliveryJob.perform_later(
              endpoint: subscription.endpoint,
              p256dh_key: subscription.p256dh_key,
              auth_key: subscription.auth_key,
              payload: JSON.generate(payload)
            )
          end
        end

        def deliver_now(endpoint:, p256dh_key:, auth_key:, payload:)
          Webpush.payload_send(
            message: payload,
            endpoint: endpoint,
            p256dh: p256dh_key,
            auth: auth_key,
            vapid: {
              subject: ENV.fetch("VAPID_SUBJECT", "mailto:noreply@tayaway.nl"),
              public_key: ENV.fetch("VAPID_PUBLIC_KEY"),
              private_key: ENV.fetch("VAPID_PRIVATE_KEY")
            }
          )
        rescue Webpush::ExpiredSubscription, Webpush::InvalidSubscription
          # Browser revoked the subscription — drop it so we stop trying.
          PushSubscription.delete_endpoint(endpoint)
        end

        def configured?
          !ENV["VAPID_PUBLIC_KEY"].to_s.empty? && !ENV["VAPID_PRIVATE_KEY"].to_s.empty?
        end
      end

      class DeliveryJob < Jobs::Base
        def call(endpoint:, p256dh_key:, auth_key:, payload:)
          Notifications::Channels::Push.deliver_now(
            endpoint: endpoint,
            p256dh_key: p256dh_key,
            auth_key: auth_key,
            payload: payload
          )
        end
      end
    end
  end
end
