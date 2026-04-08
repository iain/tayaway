# frozen_string_literal: true

class SettlementTransferPolicy
  include Policy

  ACTIONS = %i[mark_paid generate_qr].freeze

  def initialize(transfer, membership:, **)
    @transfer = transfer
    @recipient = transfer.to_user_id == membership.user_id
    @sender = transfer.from_user_id == membership.user_id
  end

  def mark_paid
    if @recipient
      Success()
    else
      Failure(:not_recipient)
    end
  end

  def generate_qr
    if @sender
      Success()
    else
      Failure(:not_sender)
    end
  end
end
