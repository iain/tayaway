# typed: true
# frozen_string_literal: true

# Read-only ChoreRoster model.
class ChoreRoster < T::Struct
  extend T::Sig

  const :id, UUID
  const :event_id, UUID
  const :user_id, T.nilable(UUID)
  const :created_at, Time
  const :updated_at, Time

  sig { params(chore_ids: T::Array[String]).returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash(chore_ids:)
    {
      id: id.to_s,
      objectType: "choreRoster",
      eventId: event_id.to_s,
      userId: user_id&.to_s,
      choreIds: chore_ids,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig
    include Result::Methods
    include Findable

    sig { params(id: T.any(String, UUID)).returns(T.nilable(ChoreRoster)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(event_id: T.any(String, UUID)).returns(T.nilable(ChoreRoster)) }
    def find_by_event(event_id)
      dataset.where(event_id: event_id).first
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[ChoreRoster]) }
    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("chore_rosters.updated_at > ?", since))
        .select_all(:chore_rosters)
        .all
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:chore_rosters].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(ChoreRoster) }
    def from_row(row)
      ChoreRoster.new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
