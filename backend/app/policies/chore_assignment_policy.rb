# frozen_string_literal: true

class ChoreAssignmentPolicy
  include Policy

  ACTIONS = %i[edit delete].freeze

  def initialize(_assignment, membership:, **)
  end

  def edit
    Success()
  end

  def delete
    Success()
  end
end
