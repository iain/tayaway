# frozen_string_literal: true

# Explicit timezones.
#
# - Workspaces carry a default zone (the group's home base).
# - Events resolve their own zone — a trip happens in a physical place, derived
#   from its location, falling back to the workspace.
# - Users carry an optional, display-only preference; NULL means "follow the
#   viewer's device", so a travelling user's local time stays right.
#
# The workspace/event column defaults match the deployment's home zone so that
# inserts from the old code still serving traffic during the deploy — which
# don't know about the column — stay valid, and existing rows backfill to it.
Sequel.migration do
  change do
    alter_table(:workspaces) do
      add_column :timezone, :text, null: false, default: "Europe/Amsterdam"
    end
    alter_table(:events) do
      add_column :timezone, :text, null: false, default: "Europe/Amsterdam"
    end
    alter_table(:users) do
      add_column :timezone, :text, null: true
    end
  end
end
