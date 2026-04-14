# frozen_string_literal: true

# Read-only Chore model.
class Chore
  attr_reader :id, :chore_roster_id, :name, :people_per_day, :position, :created_at, :updated_at

  def initialize(
    id:,
    chore_roster_id:,
    name:,
    people_per_day:,
    position:,
    created_at:,
    updated_at:
  )
    @id = id
    @chore_roster_id = chore_roster_id
    @name = name
    @people_per_day = people_per_day
    @position = position
    @created_at = created_at
    @updated_at = updated_at
  end

  class << self
    include Dry::Monads[:result]
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_roster(chore_roster_id)
      dataset.where(chore_roster_id: chore_roster_id).order(:position).all
    end

    def for_rosters(chore_roster_ids)
      return [] if chore_roster_ids.empty?

      dataset.where(chore_roster_id: chore_roster_ids).order(:chore_roster_id, :position).all
    end

    def ids_for_roster(chore_roster_id)
      DB[:chores].where(chore_roster_id: chore_roster_id).order(:position).select_map(:id)
    end

    def max_position(chore_roster_id)
      DB[:chores].where(chore_roster_id: chore_roster_id).max(:position) || 0.0
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:chore_rosters, id: :chore_roster_id)
        .join(:events, id: Sequel[:chore_rosters][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("chores.updated_at > ?", since))
        .select_all(:chores)
        .all
    end

    private

    def dataset
      DB[:chores].with_row_proc(method(:from_row))
    end

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
