# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent when a passkey is registered on the account. Acts as a
    # tripwire: a passkey added by an attacker who briefly held a session
    # lets them keep getting in even after the session is revoked, so the
    # account owner needs to know it happened.
    module PasskeyAdded
      class << self
        def key = :passkey_added
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(passkey_name:, session_url:, **)
          {
            title: "Passkey added to your account",
            body: passkey_name && !passkey_name.empty? ? "“#{passkey_name}”" : "A new passkey was registered.",
            href: session_url
          }
        end

        def build_email(email:, recipient_name:, passkey_name:, session_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          name_display = passkey_name && !passkey_name.empty? ? passkey_name : "a new passkey"

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "Passkey added to your Tayaway account",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              #{name_display} was just registered on your account.

              If this was you, no action is needed. If not, remove the passkey right away.

              Manage passkeys: #{session_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Passkey added"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "#{Mailers::EmailRenderer.escape(name_display)} was just registered on your account.",
                style: :highlight
              ),
              Mailers::EmailRenderer.paragraph(
                "If this was you, no action is needed. If not, remove the passkey right away."
              ),
              Mailers::EmailRenderer.button(text: "Manage passkeys", href: session_url)
            ].join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, passkey_name:, session_url:)
          message = PasskeyAdded.build_email(
            email: email,
            recipient_name: recipient_name,
            passkey_name: passkey_name,
            session_url: session_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
