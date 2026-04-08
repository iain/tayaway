# frozen_string_literal: true

class EventPolicy
  include Policy

  ACTIONS = %i[edit delete create_poll create_expense create_settlement
               create_rsvp create_chore_roster].freeze

  def initialize(event, membership:, **)
    @event = event
    @owner = event.user_id == membership.user_id
  end

  def edit
    if @owner
      Success()
    else
      Failure(:not_owner)
    end
  end

  def delete
    if @owner
      Success()
    else
      Failure(:not_owner)
    end
  end

  def create_poll
    if @owner
      Success()
    else
      Failure(:not_owner)
    end
  end

  def create_expense
    Success()
  end

  def create_settlement
    Success()
  end

  def create_rsvp
    Success()
  end

  def create_chore_roster
    Success()
  end
end
