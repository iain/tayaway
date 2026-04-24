# frozen_string_literal: true

class SettlementTransferPolicy
  include Policy

  ACTIONS = %i[mark_paid generate_qr].freeze

  def initialize(transfer, membership:, **)
    @transfer = transfer
    @recipient = transfer.to_user_id == membership.user_id
    @sender = transfer.from_user_id == membership.user_id
    @superseded = !transfer.superseded_at.nil?
  end

  def mark_paid
    if @superseded
      Failure(:superseded)
    elsif @recipient
      Success()
    else
      Failure(:not_recipient)
    end
  end

  def generate_qr
    if @superseded
      Failure(:superseded)
    elsif @sender
      Success()
    else
      Failure(:not_sender)
    end
  end
end
