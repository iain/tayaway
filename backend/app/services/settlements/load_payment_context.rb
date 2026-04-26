# frozen_string_literal: true

module Settlements
  # Authorizes the requesting membership to view payment details for a
  # transfer (sender of an unpaid, non-superseded transfer) and loads the
  # recipient/event needed to expose the IBAN or build a QR. Centralised so
  # every payment-info path enforces the same rule about who is allowed to
  # see the recipient's IBAN. The recipient may not have an IBAN configured;
  # callers decide which fields they can populate from what's available.
  module LoadPaymentContext
    class << self
      include Dry::Monads[:result]

      def call(transfer_id:, membership:)
        Success()
          .bind { SettlementTransfer.find_result(transfer_id) }
          .bind { |transfer| SettlementTransferPolicy.enforce(:generate_qr, transfer, membership: membership) }
          .bind { |transfer| load(transfer) }
      end

      private

      def load(transfer)
        settlement = Settlement.find(transfer.settlement_id)
        return Failure(ServiceError.not_found("Settlement not found")) unless settlement

        event = Event.find(settlement.event_id)
        return Failure(ServiceError.not_found("Event not found")) unless event

        recipient = User.find(transfer.to_user_id)
        return Failure(ServiceError.not_found("Recipient not found")) unless recipient

        Success(transfer: transfer, event: event, recipient: recipient)
      end
    end
  end
end
