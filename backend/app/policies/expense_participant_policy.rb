# frozen_string_literal: true

class ExpenseParticipantPolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(_participant, membership:, **)
  end

  def delete
    Success()
  end
end
