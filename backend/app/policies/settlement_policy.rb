# frozen_string_literal: true

class SettlementPolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(settlement, membership:, event: nil, has_successor: false, **)
    @settlement = settlement
    @event = event || Event.find(settlement.event_id)
    @creator = settlement.user_id == membership.user_id
    @event_owner = @event&.user_id == membership.user_id
    @has_successor = has_successor
  end

  # Only the chain tip can be deleted: a mid-chain delete would orphan the
  # successor's superseded transfers (only the successor's own deletion is
  # allowed to un-supersede them) and break the chain math invariant.
  def delete
    if @has_successor
      Failure(:not_tip)
    elsif @creator || @event_owner
      Success()
    else
      Failure(:not_creator_or_event_owner)
    end
  end
end
