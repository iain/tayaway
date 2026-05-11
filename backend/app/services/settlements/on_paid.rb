# frozen_string_literal: true

module Settlements
  # Sent to the counterparty when one side asserts a net balance was paid.
  # `actor_role` tells the kind which copy to render — debtor side and
  # creditor side phrase it differently.
  module OnPaid
    class << self
      def call(workspace_id:, actor_user_id:, counterparty_user_id:, amount:, actor_role:)
        Notifications::Safely.deliver(context: "Settlements::OnPaid") do
          counterparty = User.find(counterparty_user_id)
          actor = User.find(actor_user_id)
          return unless counterparty && actor

          Notifications::Dispatch.call(
            kind: :payment_status_changed,
            user_id: counterparty.id.to_s,
            workspace_id: workspace_id.to_s,
            data: {
              email: counterparty.email.to_s,
              recipient_name: counterparty.name,
              action: "paid",
              actor_name: actor.name || actor.email.to_s,
              amount: amount.to_f,
              actor_role: actor_role,
              settle_up_url: "#{ENV.fetch("FRONTEND_URL", "https://tayaway.nl")}/settle-up"
            }
          )
        end
      end
    end
  end
end
