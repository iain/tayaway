# frozen_string_literal: true

module Notifications
  module Kinds
    # Invitation to join a workspace. A recipient who's already a Tayaway
    # user can opt out of further invite emails; the initial send to a
    # brand-new email still works because the dispatcher skips preference
    # lookup when no `user_id` is supplied.
    module WorkspaceInvite
      class << self
        def key = :workspace_invite
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(invite_link:, workspace_name:, **)
          {
            title: "Invitation to #{workspace_name}",
            body: "Tap to accept and join.",
            href: invite_link
          }
        end

        def build_email(email:, invite_link:, workspace_name:, name: nil)
          greeting = name ? "Hi #{name}," : nil

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "Join #{workspace_name} on Tayaway",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting ? "#{greeting}\n\n" : ""}You've been invited to join #{workspace_name} on Tayaway

              Click the link below to accept the invitation:

              #{invite_link}

              This link expires in 24 hours. If you weren't expecting this, you can safely ignore this email.
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Join #{workspace_name}"),
              greeting ? Mailers::EmailRenderer.paragraph(greeting, style: :tight) : nil,
              Mailers::EmailRenderer.paragraph(
                "You’ve been invited to join <strong>#{Mailers::EmailRenderer.escape(workspace_name)}</strong> on Tayaway.",
                raw: true
              ),
              Mailers::EmailRenderer.button(text: "Accept invitation", href: invite_link),
              Mailers::EmailRenderer.muted_link(prefix: "Or copy and paste this link:", href: invite_link),
              Mailers::EmailRenderer.footer("This link expires in 24 hours. If you weren’t expecting this, you can safely ignore this email.")
            ].compact.join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, invite_link:, workspace_name:, name: nil)
          message = WorkspaceInvite.build_email(
            email: email,
            invite_link: invite_link,
            workspace_name: workspace_name,
            name: name
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
