# frozen_string_literal: true

class VotePolicy
  include Policy

  ACTIONS = %i[delete].freeze

  def initialize(vote, membership:, **)
    @creator = vote.user_id == membership.user_id
  end

  def delete
    if @creator
      Success()
    else
      Failure(:not_creator)
    end
  end
end
