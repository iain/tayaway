# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent when a sign-in lands on a (browser, country) combination the
    # user hasn't seen recently. The detection lives in
    # `Auth::SessionCreator` because that's the natural choke point —
    # every successful auth path funnels through it.
    module NewSession
      class << self
        def key = :new_session
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(browser_name:, os_name:, city:, country:, session_url:, **)
          {
            title: "New sign-in to your account",
            body: device_summary(browser_name, os_name, city, country),
            href: session_url
          }
        end

        def build_email(email:, recipient_name:, browser_name:, os_name:, city:, country:, session_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          summary = device_summary(browser_name, os_name, city, country)

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "New sign-in to your Tayaway account",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              Your account was just signed in to from a place we haven't seen before:
              #{summary}

              If this was you, no action is needed. If not, sign in and revoke this session right away.

              Manage sessions: #{session_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("New sign-in"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "Your account was just signed in to from a place we haven’t seen before:",
                style: :tight
              ),
              Mailers::EmailRenderer.paragraph(summary, style: :highlight),
              Mailers::EmailRenderer.paragraph(
                "If this was you, no action is needed. If not, revoke this session right away."
              ),
              Mailers::EmailRenderer.button(text: "Manage sessions", href: session_url)
            ].join
          )
        end

        private

        def device_summary(browser_name, os_name, city, country)
          parts = []
          if browser_name && os_name
            parts << "#{browser_name} on #{os_name}"
          elsif browser_name
            parts << browser_name
          elsif os_name
            parts << os_name
          end
          location = [city, country].compact.reject(&:empty?).join(", ")
          parts << "in #{location}" unless location.empty?
          parts.empty? ? "an unknown device" : parts.join(" ")
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, browser_name:, os_name:, city:, country:, session_url:)
          message = NewSession.build_email(
            email: email,
            recipient_name: recipient_name,
            browser_name: browser_name,
            os_name: os_name,
            city: city,
            country: country,
            session_url: session_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
