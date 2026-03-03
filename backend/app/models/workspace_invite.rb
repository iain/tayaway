# typed: true
# frozen_string_literal: true

# Read-only workspace invite model.
class WorkspaceInvite < T::Struct
  extend T::Sig

  EXPIRY_HOURS = 24

  const :id, UUID
  const :workspace_id, UUID
  const :invited_by, T.nilable(UUID)
  const :email, EmailAddress
  const :name, T.nilable(String)
  const :token, String
  const :expires_at, Time
  const :accepted_at, T.nilable(Time)
  const :last_reminded_at, T.nilable(Time)
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "workspaceInvite",
      workspaceId: workspace_id.to_s,
      invitedBy: invited_by&.to_s,
      email: email.to_s,
      name: name,
      expiresAt: expires_at.iso8601(3),
      acceptedAt: accepted_at&.iso8601(3),
      lastRemindedAt: last_reminded_at&.iso8601(3),
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(WorkspaceInvite)) }
    def find(id)
      dataset.where(id: id).first
    end

    # Find a valid (not expired, not accepted) invite by token hash and email.
    sig { params(token_hash: String, email: String).returns(T.nilable(WorkspaceInvite)) }
    def find_valid(token_hash, email)
      dataset
        .where(token: token_hash, email: email)
        .where(accepted_at: nil)
        .where(Sequel[:expires_at] > Time.now)
        .first
    end

    # Find a pending (not accepted) invite for a given workspace and email.
    sig { params(workspace_id: T.any(String, UUID), email: String).returns(T.nilable(WorkspaceInvite)) }
    def find_pending(workspace_id, email)
      dataset
        .where(workspace_id: workspace_id, email: email)
        .where(accepted_at: nil)
        .first
    end

    # List all non-accepted invites (pending + expired) for a workspace.
    sig { params(workspace_id: T.any(String, UUID)).returns(T::Array[WorkspaceInvite]) }
    def all_non_accepted_for_workspace(workspace_id)
      dataset
        .where(workspace_id: workspace_id)
        .where(accepted_at: nil)
        .order(:created_at)
        .all
    end

    # Return non-accepted invites changed since a given timestamp (for pool sync).
    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[WorkspaceInvite]) }
    def changed_since(workspace_id, since)
      dataset
        .where(workspace_id: workspace_id)
        .where(accepted_at: nil)
        .where(Sequel.lit("updated_at > ?", since))
        .all
    end

    private

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(WorkspaceInvite) }
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

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:workspace_invites].with_row_proc(method(:from_row))
    end
  end
end
