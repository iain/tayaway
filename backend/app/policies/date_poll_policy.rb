# frozen_string_literal: true

class DatePollPolicy
  include Policy

  ACTIONS = %i[close reopen create_date_range].freeze

  def initialize(date_poll, membership:, event: nil, **)
    @date_poll = date_poll
    @event = event || Event.find(date_poll.event_id)
    @event_owner = @event&.user_id == membership.user_id
  end

  def close
    if @event_owner
      Success()
    else
      Failure(:not_event_owner)
    end
  end

  def reopen
    if @event_owner
      Success()
    else
      Failure(:not_event_owner)
    end
  end

  def create_date_range
    if @event_owner
      Success()
    else
      Failure(:not_event_owner)
    end
  end
end
