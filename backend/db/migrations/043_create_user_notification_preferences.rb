# frozen_string_literal: true

# Per-user, per-(notification kind, channel) overrides of the kind's
# default channel set. Storage is a sparse override layer: a missing row
# means "use the kind's default", so introducing a new kind or a new user
# requires no backfill. `kind` and `channel` are free-form text rather
# than enums to keep the registry the single source of truth — adding a
# notification kind or a channel doesn't take a schema change.
Sequel.migration do
  up do
    create_table(:user_notification_preferences) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      String :kind, null: false, text: true
      String :channel, null: false, text: true
      TrueClass :enabled, null: false
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

      unique %i[user_id kind channel]
    end

    run <<~SQL
      CREATE TRIGGER update_user_notification_preferences_updated_at
      BEFORE UPDATE ON user_notification_preferences
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:user_notification_preferences)
  end
end
