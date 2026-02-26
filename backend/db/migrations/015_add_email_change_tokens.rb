# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:email_change_tokens) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      String :token, null: false, unique: true, size: 64
      column :email, :citext, null: false
      column :new_email, :citext, null: false
      column :expires_at, :timestamptz, null: false
      column :used_at, :timestamptz
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :token
    end

    run <<~SQL
      CREATE TRIGGER update_email_change_tokens_updated_at
      BEFORE UPDATE ON email_change_tokens
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:email_change_tokens)
  end
end
