# frozen_string_literal: true

module Settlements
  # Sent to the counterparty when one side reverses a paid assertion.
  # Same kind as OnPaid (the user-facing preference is "tell me when a
  # payment's status changes"), distinguished only by the `action: "unpaid"`
  # field — the kind's copy branches on it.
  module OnUnpaid
    class << self
      def call(workspace_id:, actor_user_id:, counterparty_user_id:, amount:, actor_role:)
        Notifications::Safely.deliver(context: "Settlements::OnUnpaid") do
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
              action: "unpaid",
              actor_name: actor.name || actor.email.to_s,
              amount: amount,
              actor_role: actor_role,
              settle_up_url: "#{FRONTEND_URL}/settle-up"
            }
          )
        end
      end
    end
  end
end
