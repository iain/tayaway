# frozen_string_literal: true

class EventPolicy
  include Policy

  ACTIONS = %i[edit delete create_poll create_expense create_settlement
               create_attendance create_chore_roster].freeze

  def initialize(event, membership:, has_expenses: false, **)
    @event = event
    @owner = event.user_id == membership.user_id
    @admin_or_owner = %w[admin owner].include?(membership.role)
    @has_expenses = has_expenses
  end

  def edit
    if @owner || @admin_or_owner
      Success()
    else
      Failure(:not_owner)
    end
  end

  def delete
    if !(@owner || @admin_or_owner)
      Failure(:not_owner)
    elsif @has_expenses
      Failure(:has_expenses)
    else
      Success()
    end
  end

  def create_poll
    if @owner || @admin_or_owner
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

  def create_attendance
    Success()
  end

  def create_chore_roster
    Success()
  end
end
