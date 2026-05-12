# frozen_string_literal: true

module Settlements
  # Fans a settlement_created notification out to both sides of every
  # transfer in the freshly-created settlement. Debtor and creditor get
  # different copy from the same kind; the recipient_role field switches
  # between the two views.
  module OnCreated
    class << self
      def call(transfers:, event:, workspace_id:)
        Notifications::Safely.deliver(context: "Settlements::OnCreated") do
          return if transfers.empty?

          user_ids = transfers.flat_map { |t| [t[:from_user_id], t[:to_user_id]] }.uniq
          users_by_id = User.for_ids(user_ids).each_with_object({}) { |u, h| h[u.id.to_s] = u }
          event_url = "#{APP_CONFIG.frontend_url}/events/#{event.id}"

          transfers.each do |transfer|
            debtor = users_by_id[transfer[:from_user_id].to_s]
            creditor = users_by_id[transfer[:to_user_id].to_s]
            next unless debtor && creditor

            dispatch(
              recipient: debtor, counterparty: creditor, recipient_role: "debtor",
              amount: transfer[:amount], event: event, event_url: event_url, workspace_id: workspace_id
            )
            dispatch(
              recipient: creditor, counterparty: debtor, recipient_role: "creditor",
              amount: transfer[:amount], event: event, event_url: event_url, workspace_id: workspace_id
            )
          end
        end
      end

      private

      def dispatch(recipient:, counterparty:, recipient_role:, amount:, event:, event_url:, workspace_id:)
        Notifications::Dispatch.call(
          kind: :settlement_created,
          user_id: recipient.id.to_s,
          workspace_id: workspace_id.to_s,
          data: {
            email: recipient.email.to_s,
            recipient_name: recipient.name,
            counterparty_name: counterparty.name || counterparty.email.to_s,
            recipient_role: recipient_role,
            amount: amount.to_f,
            event_name: event.name,
            event_url: event_url
          }
        )
      end
    end
  end
end
