# frozen_string_literal: true

class WorkspacePolicy
  include Policy

  ACTIONS = %i[create_event create_task_list invite manage_members view_audit_log].freeze

  def initialize(_workspace, membership:, **)
    @admin_or_owner = %w[admin owner].include?(membership.role)
    @owner = membership.role == "owner"
  end

  def create_event
    Success()
  end

  def create_task_list
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

  # Audit rows expose every member's actions (including denied attempts),
  # so reading them is reserved for the workspace owner rather than admins.
  def view_audit_log
    if @owner
      Success()
    else
      Failure(:not_workspace_owner)
    end
  end
end
