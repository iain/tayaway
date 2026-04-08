# frozen_string_literal: true

class ChoreRosterPolicy
  include Policy

  ACTIONS = %i[edit delete create_chore].freeze

  def initialize(roster, membership:, **)
    @creator = roster&.user_id == membership.user_id
  end

  def edit
    Success()
  end

  def delete
    if @creator
      Success()
    else
      Failure(:not_creator)
    end
  end

  def create_chore
    Success()
  end
end
