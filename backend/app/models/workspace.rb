# typed: true
# frozen_string_literal: true

# Read-only workspace model.
class Workspace < T::Struct
  extend T::Sig

  const :id, UUID
  const :name, String
  const :created_at, Time
  const :updated_at, Time

  sig { params(membership_ids: T::Array[String]).returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash(membership_ids:)
    {
      id: id.to_s,
      objectType: "workspace",
      name: name,
      membershipIds: membership_ids,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(Workspace)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T.nilable(Workspace)) }
    def updated_since(workspace_id, since)
      dataset.where(id: workspace_id).where(Sequel.lit("updated_at > ?", since)).first
    end

    sig { params(user_id: T.any(String, UUID)).returns(T::Array[Workspace]) }
    def for_user(user_id)
      workspace_ids = DB[:workspace_memberships]
                      .where(user_id: user_id)
                      .select(:workspace_id)
      dataset.where(id: workspace_ids).order(:name).all
    end

    sig { returns(T::Array[Workspace]) }
    def all_ordered
      dataset.order(:name).all
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:workspaces].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(Workspace) }
    def from_row(row)
      Workspace.new(
        id: UUID.new(row[:id]),
        name: row[:name],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
