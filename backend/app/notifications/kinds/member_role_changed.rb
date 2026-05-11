# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to a member whose workspace role just changed (e.g. promoted
    # to admin or demoted to member). Visible elevation/demotion is
    # security-relevant — knowing your access changed matters even when
    # you'd rather not see other notifications.
    module MemberRoleChanged
      class << self
        def key = :member_role_changed
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(workspace_name:, new_role:, workspace_url:, **)
          {
            title: "Your role in #{workspace_name} is now #{new_role.capitalize}",
            body: "Your access in this workspace has changed.",
            href: workspace_url
          }
        end

        def build_email(email:, recipient_name:, workspace_name:, old_role:, new_role:, workspace_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "Your role in #{workspace_name} is now #{new_role.capitalize}",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              Your role in #{workspace_name} changed from #{old_role.capitalize} to #{new_role.capitalize}.

              View workspace: #{workspace_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Role updated"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "Your role in <strong>#{Mailers::EmailRenderer.escape(workspace_name)}</strong> changed:",
                style: :tight,
                raw: true
              ),
              Mailers::EmailRenderer.paragraph(
                "#{old_role.capitalize} → #{new_role.capitalize}",
                style: :highlight
              ),
              Mailers::EmailRenderer.button(text: "View workspace", href: workspace_url)
            ].join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, workspace_name:, old_role:, new_role:, workspace_url:)
          message = MemberRoleChanged.build_email(
            email: email,
            recipient_name: recipient_name,
            workspace_name: workspace_name,
            old_role: old_role,
            new_role: new_role,
            workspace_url: workspace_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
