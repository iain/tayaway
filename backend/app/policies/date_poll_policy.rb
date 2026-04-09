# frozen_string_literal: true

class DatePollPolicy
  include Policy

  ACTIONS = %i[close reopen create_date_range].freeze

  def initialize(date_poll, membership:, event: nil, **)
    @date_poll = date_poll
    @event = event || Event.find(date_poll.event_id)
    @event_owner = @event&.user_id == membership.user_id
  end

  def close = require_event_owner

  def reopen = require_event_owner

  def create_date_range = require_event_owner

  private

  def require_event_owner
    if @event_owner
      Success()
    else
      Failure(:not_event_owner)
    end
  end
end
