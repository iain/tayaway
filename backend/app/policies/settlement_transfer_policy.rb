# frozen_string_literal: true

class SettlementTransferPolicy
  include Policy

  ACTIONS = %i[mark_paid].freeze

  def initialize(transfer, membership:, **)
    @transfer = transfer
    @recipient = transfer.to_user_id == membership.user_id
  end

  def mark_paid
    if @recipient
      Success()
    else
      Failure(:not_recipient)
    end
  end
end
