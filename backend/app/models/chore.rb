# typed: true
# frozen_string_literal: true

# Read-only Chore model.
class Chore < T::Struct
  extend T::Sig

  const :id, UUID
  const :chore_roster_id, UUID
  const :name, String
  const :people_per_day, Integer
  const :position, Float
  const :created_at, Time
  const :updated_at, Time

  sig { params(assignment_ids: T::Array[String]).returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash(assignment_ids:)
    {
      id: id.to_s,
      objectType: "chore",
      choreRosterId: chore_roster_id.to_s,
      name: name,
      peoplePerDay: people_per_day,
      position: position,
      assignmentIds: assignment_ids,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig
    include Result::Methods

    sig { params(id: T.any(String, UUID)).returns(T.nilable(Chore)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(chore_roster_id: T.any(String, UUID)).returns(T::Array[Chore]) }
    def for_roster(chore_roster_id)
      dataset.where(chore_roster_id: chore_roster_id).order(:position).all
    end

    sig { params(chore_roster_id: T.any(String, UUID)).returns(T::Array[String]) }
    def ids_for_roster(chore_roster_id)
      DB[:chores].where(chore_roster_id: chore_roster_id).order(:position).select_map(:id)
    end

    sig { params(chore_roster_id: T.any(String, UUID)).returns(Float) }
    def max_position(chore_roster_id)
      DB[:chores].where(chore_roster_id: chore_roster_id).max(:position) || 0.0
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[Chore]) }
    def changed_since(workspace_id, since)
      dataset
        .join(:chore_rosters, id: :chore_roster_id)
        .join(:events, id: Sequel[:chore_rosters][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("chores.updated_at > ?", since))
        .select_all(:chores)
        .all
    end

    sig { params(id: T.any(String, UUID)).returns(Result[Chore, ServiceError]) }
    def find_result(id)
      chore = find(id)
      if chore
        T.cast(Success(chore), Result[Chore, ServiceError])
      elsif DB[:deleted_items].where(object_type: "chore", object_id: id).first
        T.cast(Failure(ServiceError.gone("Chore not found")), Result[Chore, ServiceError])
      else
        T.cast(Failure(ServiceError.not_found("Chore not found")), Result[Chore, ServiceError])
      end
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:chores].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(Chore) }
    def from_row(row)
      Chore.new(
        id: UUID.new(row[:id]),
        chore_roster_id: UUID.new(row[:chore_roster_id]),
        name: row[:name],
        people_per_day: row[:people_per_day],
        position: row[:position].to_f,
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
