# typed: true
# frozen_string_literal: true

# Read-only workspace membership model (join table for users <-> workspaces).
class WorkspaceMembership < T::Struct
  extend T::Sig

  const :id, UUID
  const :workspace_id, UUID
  const :user_id, UUID
  const :role, String
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "workspaceMembership",
      workspaceId: workspace_id.to_s,
      userId: user_id.to_s,
      role: role,
      createdAt: created_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(WorkspaceMembership)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(workspace_id: T.any(String, UUID)).returns(T::Array[WorkspaceMembership]) }
    def for_workspace(workspace_id)
      dataset.where(workspace_id: workspace_id).order(:created_at).all
    end

    sig { params(user_id: T.any(String, UUID)).returns(T::Array[WorkspaceMembership]) }
    def for_user(user_id)
      dataset.where(user_id: user_id).order(:created_at).all
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[WorkspaceMembership]) }
    def updated_since(workspace_id, since)
      dataset.where(workspace_id: workspace_id).where(Sequel.lit("updated_at > ?", since)).all
    end

    sig { params(workspace_id: T.any(String, UUID)).returns(T::Array[String]) }
    def ids_for_workspace(workspace_id)
      DB[:workspace_memberships]
        .where(workspace_id: workspace_id)
        .select_map(:id)
    end

    # Returns { user_id_str => membership_id_str } for a workspace.
    # Used by PoolSerializer to map user_id → membership_id.
    sig { params(workspace_id: T.any(String, UUID)).returns(T::Hash[String, String]) }
    def member_id_lookup(workspace_id)
      DB[:workspace_memberships]
        .where(workspace_id: workspace_id)
        .select_hash(:user_id, :id)
        .transform_keys(&:to_s)
        .transform_values(&:to_s)
    end

    sig do
      params(
        workspace_id: T.any(String, UUID),
        user_id: T.any(String, UUID)
      ).returns(T.nilable(WorkspaceMembership))
    end
    def find_by_workspace_and_user(workspace_id, user_id)
      dataset.where(workspace_id: workspace_id, user_id: user_id).first
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:workspace_memberships].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(WorkspaceMembership) }
    def from_row(row)
      WorkspaceMembership.new(
        id: UUID.new(row[:id]),
        workspace_id: UUID.new(row[:workspace_id]),
        user_id: UUID.new(row[:user_id]),
        role: row[:role],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
