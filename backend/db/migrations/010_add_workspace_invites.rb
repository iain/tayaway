# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:workspace_invites) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :workspace_id, :workspaces, type: :uuid, null: false, on_delete: :cascade
      foreign_key :invited_by, :users, type: :uuid, null: true, on_delete: :set_null
      column :email, :citext, null: false
      column :token, String, null: false
      column :expires_at, "timestamptz", null: false
      column :accepted_at, "timestamptz", null: true
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
    end

    # One pending invite per email per workspace
    run <<~SQL
      CREATE UNIQUE INDEX index_workspace_invites_pending
        ON workspace_invites (workspace_id, email)
        WHERE accepted_at IS NULL;
    SQL

    run <<~SQL
      CREATE TRIGGER update_workspace_invites_updated_at
        BEFORE UPDATE ON workspace_invites
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:workspace_invites)
  end
end
