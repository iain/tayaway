# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent when a passkey is registered on or removed from the account.
    # `action: "added"` and `action: "removed"` use the same kind because
    # the user-facing decision is "tell me when my credential set
    # changes" — opting into one direction without the other doesn't
    # reflect a real preference. The email channel is forced because a
    # passkey added by an attacker who briefly held a session lets them
    # keep getting in even after the session is revoked, so silencing the
    # alert via the preferences API would defeat the tripwire.
    module PasskeyChanged
      class << self
        def key = :passkey_changed
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def forced_channels = %i[email]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(action:, passkey_name:, session_url:, **)
          name_phrase = passkey_name && !passkey_name.empty? ? "“#{passkey_name}”" : "A passkey"
          {
            title: action == "added" ? "Passkey added to your account" : "Passkey removed from your account",
            body: action == "added" ? "#{name_phrase} was registered." : "#{name_phrase} was removed.",
            href: session_url
          }
        end

        def build_email(email:, recipient_name:, action:, passkey_name:, session_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          name_display = passkey_name && !passkey_name.empty? ? passkey_name : (action == "added" ? "a new passkey" : "A passkey")
          subject = action == "added" ? "Passkey added to your Tayaway account" : "Passkey removed from your Tayaway account"
          heading = action == "added" ? "Passkey added" : "Passkey removed"
          body_line =
            if action == "added"
              "#{name_display} was just registered on your account."
            else
              "#{name_display} was just removed from your account."
            end
          followup =
            if action == "added"
              "If this was you, no action is needed. If not, remove the passkey right away."
            else
              "If this was you, no action is needed. If not, sign in and review your account security."
            end

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: subject,
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              #{body_line}

              #{followup}

              Manage passkeys: #{session_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading(heading),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(body_line, style: :highlight),
              Mailers::EmailRenderer.paragraph(followup),
              Mailers::EmailRenderer.button(text: "Manage passkeys", href: session_url)
            ].join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, action:, passkey_name:, session_url:)
          message = PasskeyChanged.build_email(
            email: email,
            recipient_name: recipient_name,
            action: action,
            passkey_name: passkey_name,
            session_url: session_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
