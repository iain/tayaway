# frozen_string_literal: true

# Read-only ChoreAssignment model. The holder is the person behind
# attendance_id (doc/attendances.md); user_id mirrors the attendance's user
# for old clients until the column drops, and may be nil on legacy rows the
# backfill has not reached.
class ChoreAssignment < Data.define(:id, :chore_id, :user_id, :attendance_id, :date, :pinned, :note, :created_at, :updated_at)
  class << self
    include Findable

    def find(id)
      dataset.where(Sequel[:chore_assignments][:id] => id).first
    end

    def for_chore(chore_id)
      dataset.where(Sequel[:chore_assignments][:chore_id] => chore_id).order(Sequel[:chore_assignments][:date]).all
    end

    def for_chores(chore_ids)
      return [] if chore_ids.empty?

      dataset.where(chore_id: chore_ids).all
    end

    def ids_for_chore(chore_id)
      DB[:chore_assignments].where(chore_id: chore_id).select_map(:id)
    end

    def for_roster(chore_roster_id)
      dataset
        .join(:chores, id: Sequel[:chore_assignments][:chore_id])
        .where(Sequel[:chores][:chore_roster_id] => chore_roster_id)
        .select_all(:chore_assignments)
        .all
    end

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

    private

    def dataset
      DB[:chore_assignments].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        chore_id: UUID.new(row[:chore_id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        attendance_id: row[:attendance_id] ? UUID.new(row[:attendance_id]) : nil,
        date: row[:date],
        pinned: row[:pinned],
        note: row[:note],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
