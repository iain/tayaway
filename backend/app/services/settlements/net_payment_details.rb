# frozen_string_literal: true

module Settlements
  # Net-pair counterpart to Settlements::PaymentDetails. Computes the live net
  # between the caller and a counterparty across the workspace, refuses to
  # serve if the caller isn't the net sender or if the amount has drifted from
  # what they expected, then returns the same shape so the existing client
  # modal can render it without a separate code path.
  module NetPaymentDetails
    REFERENCE_LIMIT_BYTES = 140

    class << self
      def call(workspace_id:, counterparty_user_id:, expected_amount:, membership:)
        Success()
          .bind { validate(counterparty_user_id, expected_amount, membership) }
          .bind { build(workspace_id, membership, counterparty_user_id, expected_amount) }
      end

      private

      def validate(counterparty_user_id, expected_amount, membership)
        if counterparty_user_id.nil? || counterparty_user_id.to_s.strip.empty?
          Failure(ServiceError.validation("counterparty_user_id is required"))
        elsif counterparty_user_id.to_s == membership.user_id.to_s
          Failure(ServiceError.validation("Cannot settle a balance with yourself"))
        elsif expected_amount.nil?
          Failure(ServiceError.validation("expected_amount is required"))
        else
          Success()
        end
      end

      def build(workspace_id, membership, counterparty_user_id, expected_amount)
        net = WorkspaceNet.compute_pair(
          workspace_id: workspace_id,
          user_a: membership.user_id,
          user_b: counterparty_user_id
        )

        if net.nil?
          return Failure(ServiceError.conflict("Nothing to pay — the balance is even"))
        end

        if net[:from_user_id] != membership.user_id.to_s
          return Failure(ServiceError.forbidden("not_sender"))
        end

        if (net[:amount] - expected_amount.to_f).abs >= WorkspaceNet::BALANCE_EPSILON
          return Failure(ServiceError.conflict(
                           "Balance has changed since you opened this page (was €#{format("%.2f", expected_amount.to_f)}, now €#{format("%.2f", net[:amount])}). Refresh and try again."
                         )
                        )
        end

        recipient = User.find(counterparty_user_id)
        return Failure(ServiceError.not_found("Recipient not found")) unless recipient

        reference = build_reference(net[:underlying_transfer_ids], workspace_id)

        base = {
          recipientName: recipient.name || recipient.email.to_s,
          amount: net[:amount],
          reference: reference,
          iban: nil,
          qrPng: nil
        }

        return Success(base) unless recipient.iban

        base[:iban] = EpcQr.format_iban(recipient.iban)
        base[:qrPng] = EpcQr.build_png_base64(
          recipient_name: recipient.name || recipient.email.to_s,
          iban: recipient.iban,
          amount: net[:amount],
          description: reference
        )

        Success(base)
      end

      def build_reference(transfer_ids, workspace_id)
        event_names = DB[:events]
                      .join(:settlements, event_id: :id)
                      .join(:settlement_transfers, settlement_id: :id)
                      .where(Sequel[:settlement_transfers][:id] => transfer_ids)
                      .distinct
                      .order(Sequel[:events][:name])
                      .select_map(Sequel[:events][:name])

        joined = event_names.join(", ")
        return joined if joined.bytesize <= REFERENCE_LIMIT_BYTES

        workspace = Workspace.find(workspace_id)
        fallback = workspace ? "#{workspace.name} settlement" : "Tayaway settlement"
        fallback.byteslice(0, REFERENCE_LIMIT_BYTES) || fallback
      end
    end
  end
end
