# frozen_string_literal: true

# Per-day "come and go" attendance.
#
# `attendance` holds the explicit set of days a member attends as a JSONB array
# of "YYYY-MM-DD" strings; NULL means "the whole event" (and, for rows written
# by older code, the contiguous start_date..end_date window still applies as a
# fallback). It supersedes the single start_date/end_date range, which is kept
# for now so the old code still serving traffic during the deploy keeps working
# and existing rows keep resolving; a later migration drops the range columns.
Sequel.migration do
  change do
    alter_table(:rsvps) do
      add_column :attendance, :jsonb, null: true
    end
  end
end
