# frozen_string_literal: true

class ChorePolicy
  include Policy

  ACTIONS = %i[edit delete].freeze

  def initialize(_chore, membership:, **)
  end

  def edit
    Success()
  end

  def delete
    Success()
  end
end
