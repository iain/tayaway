# frozen_string_literal: true

class MemberPolicy
  include Policy

  ACTIONS = %i[change_role].freeze

  def initialize(target_member, membership:, **)
    @target = target_member
    @membership = membership
    @role = membership.role
    @self_change = target_member.user_id == membership.user_id
  end

  def change_role
    if @self_change
      Failure(:cannot_change_own_role)
    elsif !%w[admin owner].include?(@role)
      Failure(:not_admin_or_owner)
    elsif @target.role == "owner" && @role != "owner"
      Failure(:cannot_change_owner)
    else
      Success()
    end
  end

  def available_roles
    if change_role.failure?
      []
    else
      case @role
      when "owner" then %w[member admin owner]
      when "admin" then %w[member admin]
      else []
      end
    end
  end

  def permissions
    super.merge(availableRoles: available_roles)
  end
end
