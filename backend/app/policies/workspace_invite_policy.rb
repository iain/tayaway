# frozen_string_literal: true

class WorkspaceInvitePolicy
  include Policy

  ACTIONS = %i[delete remind].freeze

  def initialize(_invite, membership:, **)
    @admin_or_owner = %w[admin owner].include?(membership.role)
  end

  def delete
    if @admin_or_owner
      Success()
    else
      Failure(:not_admin_or_owner)
    end
  end

  def remind
    if @admin_or_owner
      Success()
    else
      Failure(:not_admin_or_owner)
    end
  end
end
