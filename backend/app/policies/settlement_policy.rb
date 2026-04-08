# frozen_string_literal: true

class SettlementPolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(settlement, membership:, event: nil, **)
    @settlement = settlement
    @event = event || Event.find(settlement.event_id)
    @creator = settlement.user_id == membership.user_id
    @event_owner = @event&.user_id == membership.user_id
  end

  def delete
    if @creator || @event_owner
      Success()
    else
      Failure(:not_creator_or_event_owner)
    end
  end
end
