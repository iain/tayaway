# frozen_string_literal: true

class DateRangePolicy
  include Policy

  ACTIONS = %i[delete create_vote].freeze

  def initialize(date_range, membership:, event: nil, **)
    @date_range = date_range
    if event
      @event_owner = event.user_id == membership.user_id
    else
      poll = DatePoll.find(date_range.date_poll_id)
      found_event = Event.find(poll.event_id) if poll
      @event_owner = found_event&.user_id == membership.user_id
    end
  end

  def delete
    if @event_owner
      Success()
    else
      Failure(:not_event_owner)
    end
  end

  def create_vote
    Success()
  end
end
