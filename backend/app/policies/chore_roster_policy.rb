# frozen_string_literal: true

class ChoreRosterPolicy
  include Policy

  ACTIONS = %i[edit delete create_chore].freeze

  def initialize(roster, membership:, event: nil, **)
    @creator = roster&.user_id == membership.user_id
    @event = event || (roster && Event.find(roster.event_id))
    @event_owner = @event&.user_id == membership.user_id
    @admin_or_owner = %w[admin owner].include?(membership.role)
  end

  def edit
    Success()
  end

  def delete
    if @creator || @event_owner || @admin_or_owner
      Success()
    else
      Failure(:not_creator)
    end
  end

  def create_chore
    Success()
  end
end
