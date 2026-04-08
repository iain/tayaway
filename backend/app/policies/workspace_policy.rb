# frozen_string_literal: true

class WorkspacePolicy
  include Policy

  ACTIONS = %i[create_event invite manage_members].freeze

  def initialize(_workspace, membership:, **)
    @admin_or_owner = %w[admin owner].include?(membership.role)
  end

  def create_event
    Success()
  end

  def invite
    if @admin_or_owner
      Success()
    else
      Failure(:not_admin_or_owner)
    end
  end

  def manage_members
    if @admin_or_owner
      Success()
    else
      Failure(:not_admin_or_owner)
    end
  end
end
