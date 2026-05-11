# frozen_string_literal: true

# Browser push-subscription endpoints owned by a specific user. The
# `endpoint` URL is what the browser hands back from PushManager.subscribe;
# it's globally unique because the browser keeps one subscription per
# service worker, so a UNIQUE constraint guarantees re-registration just
# refreshes the existing row rather than fanning out duplicates.
Sequel.migration do
  up do
    create_table(:push_subscriptions) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      String :endpoint, null: false, text: true, unique: true
      String :p256dh_key, null: false, text: true
      String :auth_key, null: false, text: true
      String :user_agent, text: true
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    run "CREATE INDEX push_subscriptions_user ON push_subscriptions (user_id)"

    run <<~SQL
      CREATE TRIGGER update_push_subscriptions_updated_at
      BEFORE UPDATE ON push_subscriptions
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:push_subscriptions)
  end
end
