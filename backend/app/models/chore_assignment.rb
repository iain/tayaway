# typed: true
# frozen_string_literal: true

# Read-only ChoreAssignment model.
class ChoreAssignment < T::Struct
  extend T::Sig

  const :id, UUID
  const :chore_id, UUID
  const :user_id, UUID
  const :date, Date
  const :pinned, T::Boolean
  const :note, T.nilable(String)
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "choreAssignment",
      choreId: chore_id.to_s,
      userId: user_id.to_s,
      date: date.iso8601,
      pinned: pinned,
      note: note,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig
    include Result::Methods

    sig { params(id: T.any(String, UUID)).returns(T.nilable(ChoreAssignment)) }
    def find(id)
      dataset.where(Sequel[:chore_assignments][:id] => id).first
    end

    sig { params(chore_id: T.any(String, UUID)).returns(T::Array[ChoreAssignment]) }
    def for_chore(chore_id)
      dataset.where(Sequel[:chore_assignments][:chore_id] => chore_id).order(Sequel[:chore_assignments][:date]).all
    end

    sig { params(chore_id: T.any(String, UUID)).returns(T::Array[String]) }
    def ids_for_chore(chore_id)
      DB[:chore_assignments].where(chore_id: chore_id).select_map(:id)
    end

    sig { params(chore_roster_id: T.any(String, UUID)).returns(T::Array[ChoreAssignment]) }
    def for_roster(chore_roster_id)
      dataset
        .join(:chores, id: Sequel[:chore_assignments][:chore_id])
        .where(Sequel[:chores][:chore_roster_id] => chore_roster_id)
        .select_all(:chore_assignments)
        .all
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[ChoreAssignment]) }
    def changed_since(workspace_id, since)
      dataset
        .join(:chores, id: Sequel[:chore_assignments][:chore_id])
        .join(:chore_rosters, id: Sequel[:chores][:chore_roster_id])
        .join(:events, id: Sequel[:chore_rosters][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("chore_assignments.updated_at > ?", since))
        .select_all(:chore_assignments)
        .all
    end

    sig { params(id: T.any(String, UUID)).returns(Result[ChoreAssignment, ServiceError]) }
    def find_result(id)
      assignment = find(id)
      if assignment
        T.cast(Success(assignment), Result[ChoreAssignment, ServiceError])
      elsif DB[:deleted_items].where(object_type: "chore_assignment", object_id: id).first
        T.cast(Failure(ServiceError.gone("Chore assignment not found")), Result[ChoreAssignment, ServiceError])
      else
        T.cast(Failure(ServiceError.not_found("Chore assignment not found")), Result[ChoreAssignment, ServiceError])
      end
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:chore_assignments].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(ChoreAssignment) }
    def from_row(row)
      ChoreAssignment.new(
        id: UUID.new(row[:id]),
        chore_id: UUID.new(row[:chore_id]),
        user_id: UUID.new(row[:user_id]),
        date: row[:date],
        pinned: row[:pinned],
        note: row[:note],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
