# frozen_string_literal: true

class DatePollPolicy
  include Policy

  ACTIONS = %i[close reopen create_date_range].freeze

  def initialize(date_poll, membership:, event: nil, date_range_count: nil, **)
    @date_poll = date_poll
    @event = event || Event.find(date_poll.event_id)
    # Batched by DatePollSerializer on the sync path; the count query is the
    # fallback for callers that enforce the policy on a single poll.
    @date_range_count = date_range_count || DateRange.count_for_date_poll(date_poll.id)
    @poll_admin = @event&.user_id == membership.user_id ||
                  %w[admin owner].include?(membership.role)
  end

  # Actor: the poll's administrators. Invariants: a resolved poll has nothing
  # left to decide, and there is no winner to pick without date options.
  def close
    if !@poll_admin
      Failure(:not_event_owner)
    elsif @date_poll.closed_at
      Failure(:already_resolved)
    elsif @date_range_count.zero?
      Failure(:no_date_ranges)
    else
      Success()
    end
  end

  def reopen = require_poll_admin

  def create_date_range = require_poll_admin

  private

  # Whoever runs the event's poll: the event owner, plus workspace admins and
  # owners — who can already move the event's dates by hand (EventPolicy#edit),
  # so withholding the poll that sets them bought nothing.
  def require_poll_admin
    if @poll_admin
      Success()
    else
      Failure(:not_event_owner)
    end
  end
end
