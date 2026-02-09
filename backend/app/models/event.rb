# typed: true
# frozen_string_literal: true

# Read-only event model.
class Event < T::Struct
  extend T::Sig

  const :id, UUID
  const :workspace_id, UUID
  const :user_id, UUID
  const :name, String
  const :description, T.nilable(String)
  const :created_at, Time
  const :updated_at, Time

  sig { params(date_poll_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash(date_poll_id:)
    {
      id: id.to_s,
      objectType: "event",
      name: name,
      description: description,
      workspaceId: workspace_id.to_s,
      userId: user_id.to_s,
      datePollId: date_poll_id,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(Event)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(user_id: T.any(String, UUID)).returns(T::Array[Event]) }
    def for_user(user_id)
      dataset.where(user_id: user_id).order(:created_at).all
    end

    sig { params(workspace_id: T.any(String, UUID)).returns(T::Array[Event]) }
    def for_workspace(workspace_id)
      dataset.where(workspace_id: workspace_id).order(:created_at).all
    end

    sig { params(workspace_ids: T::Array[T.any(String, UUID)]).returns(T::Array[Event]) }
    def for_workspace_ids(workspace_ids)
      return [] if workspace_ids.empty?

      dataset.where(workspace_id: workspace_ids).order(:created_at).all
    end

    sig { returns(T::Array[Event]) }
    def all_ordered
      dataset.order(:created_at).all
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:events].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(Event) }
    def from_row(row)
      Event.new(
        id: UUID.new(row[:id]),
        workspace_id: UUID.new(row[:workspace_id]),
        user_id: UUID.new(row[:user_id]),
        name: row[:name],
        description: row[:description],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
