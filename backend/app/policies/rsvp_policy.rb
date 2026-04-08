# frozen_string_literal: true

class RsvpPolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(rsvp, membership:, **)
    @creator = rsvp.user_id == membership.user_id
  end

  def delete
    if @creator
      Success()
    else
      Failure(:not_creator)
    end
  end
end
