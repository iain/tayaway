# frozen_string_literal: true

class DateRangePolicy
  include Policy

  ACTIONS = %i[delete create_vote].freeze

  def initialize(date_range, membership:, event: nil, **)
    @date_range = date_range
    resolved_event = event || event_for(date_range)
    # Same rule as DatePollPolicy: the event owner plus workspace admins and
    # owners run the poll's date options.
    @poll_admin = resolved_event&.user_id == membership.user_id ||
                  %w[admin owner].include?(membership.role)
  end

  def delete
    if @poll_admin
      Success()
    else
      Failure(:not_event_owner)
    end
  end

  def create_vote
    Success()
  end

  private

  def event_for(date_range)
    poll = DatePoll.find(date_range.date_poll_id)
    Event.find(poll.event_id) if poll
  end
end
