# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to the user who issued a workspace invitation, when the
    # invitee accepts. Closure on a flow they started — and a useful
    # "they're in" signal when chasing the new member to onboard them.
    module WorkspaceInviteAccepted
      class << self
        def key = :workspace_invite_accepted
        def default_channels = %i[in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(invitee_name:, workspace_name:, workspace_url:, **)
          {
            title: "#{invitee_name} joined #{workspace_name}",
            body: "Your invitation was accepted.",
            href: workspace_url
          }
        end

        def build_email(email:, recipient_name:, invitee_name:, workspace_name:, workspace_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "#{invitee_name} joined #{workspace_name}",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              #{invitee_name} accepted your invitation and joined #{workspace_name}.

              View workspace: #{workspace_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Invitation accepted"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "<strong>#{Mailers::EmailRenderer.escape(invitee_name)}</strong> accepted your invitation and joined <strong>#{Mailers::EmailRenderer.escape(workspace_name)}</strong>.",
                style: :highlight,
                raw: true
              ),
              Mailers::EmailRenderer.button(text: "View workspace", href: workspace_url)
            ].join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, invitee_name:, workspace_name:, workspace_url:)
          message = WorkspaceInviteAccepted.build_email(
            email: email,
            recipient_name: recipient_name,
            invitee_name: invitee_name,
            workspace_name: workspace_name,
            workspace_url: workspace_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
