# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent when a passkey is removed from the account. Pairs with
    # `passkey_added` so any change to the credentials list shows up in
    # the audit trail.
    module PasskeyRemoved
      class << self
        def key = :passkey_removed
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(passkey_name:, session_url:, **)
          {
            title: "Passkey removed from your account",
            body: passkey_name && !passkey_name.empty? ? "“#{passkey_name}”" : "A passkey was removed.",
            href: session_url
          }
        end

        def build_email(email:, recipient_name:, passkey_name:, session_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          name_display = passkey_name && !passkey_name.empty? ? passkey_name : "A passkey"

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "Passkey removed from your Tayaway account",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              #{name_display} was just removed from your account.

              If this was you, no action is needed. If not, sign in and review your account security.

              Manage passkeys: #{session_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Passkey removed"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "#{Mailers::EmailRenderer.escape(name_display)} was just removed from your account.",
                style: :highlight
              ),
              Mailers::EmailRenderer.paragraph(
                "If this was you, no action is needed. If not, sign in and review your account security."
              ),
              Mailers::EmailRenderer.button(text: "Manage passkeys", href: session_url)
            ].join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, passkey_name:, session_url:)
          message = PasskeyRemoved.build_email(
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
