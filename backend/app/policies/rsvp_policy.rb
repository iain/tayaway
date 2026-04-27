# frozen_string_literal: true

class RsvpPolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(_rsvp, **)
  end

  # Any workspace member can delete any RSVP in their workspace — the actor's
  # workspace membership is established at the route layer, and an RSVP only
  # exists for an event the actor can already see.
  def delete
    Success()
  end
end
