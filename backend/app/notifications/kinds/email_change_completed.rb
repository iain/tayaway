# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to the *previous* email address when an email change finalises
    # — if the change wasn't initiated by the legitimate account owner,
    # this is the alert they'll get on the inbox they still control.
    # In-app and push reach the user (same user_id) regardless, but the
    # email channel is the security-critical one because it goes
    # somewhere the attacker can't intercept after the change.
    module EmailChangeCompleted
      class << self
        def key = :email_change_completed
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(old_email:, new_email:, session_url:, **)
          {
            title: "Your account email was changed",
            body: "from #{old_email} to #{new_email}",
            href: session_url
          }
        end

        def build_email(email:, recipient_name:, old_email:, new_email:, session_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "Your Tayaway account email was changed",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              The email address on your Tayaway account was changed from #{old_email} to #{new_email}.

              If this wasn't you, contact us immediately — your old email no longer signs you in.

              Account: #{session_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Email address changed"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "The email on your Tayaway account was changed:",
                style: :tight
              ),
              Mailers::EmailRenderer.paragraph(
                "#{Mailers::EmailRenderer.escape(old_email)} → #{Mailers::EmailRenderer.escape(new_email)}",
                style: :highlight
              ),
              Mailers::EmailRenderer.paragraph(
                "If this wasn’t you, contact us immediately — your old email no longer signs you in."
              ),
              Mailers::EmailRenderer.button(text: "View account", href: session_url)
            ].join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, old_email:, new_email:, session_url:)
          message = EmailChangeCompleted.build_email(
            email: email,
            recipient_name: recipient_name,
            old_email: old_email,
            new_email: new_email,
            session_url: session_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
