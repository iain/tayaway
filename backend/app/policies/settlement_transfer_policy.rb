# frozen_string_literal: true

class SettlementTransferPolicy
  include Policy

  ACTIONS = %i[mark_paid generate_qr].freeze

  def initialize(transfer, membership:, has_successor: false, **)
    @transfer = transfer
    @recipient = transfer.to_user_id == membership.user_id
    @sender = transfer.from_user_id == membership.user_id
    @superseded = !transfer.superseded_at.nil?
    @paid = !transfer.paid_at.nil?
    @has_successor = has_successor
  end

  def mark_paid
    if @superseded
      Failure(:superseded)
    elsif @paid && @has_successor
      # The follow-up settlement's balance math was computed treating this
      # transfer as paid. No toggle is meaningful here — unmarking would
      # silently desync the chain, marking again is a no-op.
      Failure(:locked_in_followup)
    elsif @recipient
      Success()
    else
      Failure(:not_recipient)
    end
  end

  def generate_qr
    if @superseded
      Failure(:superseded)
    elsif @paid
      # No reason to regenerate the QR for a transfer that's already settled,
      # and the IBAN it embeds shouldn't keep flowing once the bill is paid.
      Failure(:already_paid)
    elsif @sender
      Success()
    else
      Failure(:not_sender)
    end
  end
end
