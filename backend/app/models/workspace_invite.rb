# frozen_string_literal: true

# Read-only workspace invite model.
class WorkspaceInvite < Data.define(:id, :workspace_id, :invited_by, :email, :name, :token, :expires_at, :accepted_at, :last_reminded_at, :created_at, :updated_at)
  EXPIRY_HOURS = 24

  class << self
    def find(id)
      dataset.where(id: id).first
    end

    # Find a valid (not expired, not accepted) invite by token hash and email.
    def find_valid(token_hash, email)
      dataset
        .where(token: token_hash, email: email)
        .where(accepted_at: nil)
        .where(Sequel[:expires_at] > Time.now)
        .first
    end

    # Find a pending (not accepted) invite for a given workspace and email.
    def find_pending(workspace_id, email)
      dataset
        .where(workspace_id: workspace_id, email: email)
        .where(accepted_at: nil)
        .first
    end

    # List all non-accepted invites (pending + expired) for a workspace.
    def all_non_accepted_for_workspace(workspace_id)
      dataset
        .where(workspace_id: workspace_id)
        .where(accepted_at: nil)
        .order(:created_at)
        .limit(ValidationLimits::QUERY_LIMIT)
        .all
    end

    # Return non-accepted invites changed since a given timestamp (for pool sync).
    def changed_since(workspace_id, since)
      dataset
        .where(workspace_id: workspace_id)
        .where(accepted_at: nil)
        .where(Sequel.lit("updated_at > ?", since))
        .all
    end

    private

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        workspace_id: UUID.new(row[:workspace_id]),
        invited_by: row[:invited_by] ? UUID.new(row[:invited_by]) : nil,
        email: EmailAddress.new(row[:email]),
        name: row[:name],
        token: row[:token],
        expires_at: row[:expires_at],
        accepted_at: row[:accepted_at],
        last_reminded_at: row[:last_reminded_at],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end

    def dataset
      DB[:workspace_invites].with_row_proc(method(:from_row))
    end
  end
end
