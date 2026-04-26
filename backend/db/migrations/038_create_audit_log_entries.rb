# frozen_string_literal: true

Sequel.migration do
  up do
    extension :pg_enum

    create_enum(:audit_outcome, %w[success denied error])

    create_table(:audit_log_entries) do
      primary_key :id, type: :uuid, default: Sequel.function(:gen_random_uuid)

      # No FKs on actor / workspace / subject IDs: audit rows must outlive the
      # entities they refer to. We keep the IDs as opaque references and
      # accept that they may point at deleted things.
      String :actor_kind, null: false               # "user" | "system" | "invite" | …
      column :actor_user_id, :uuid, null: true
      column :workspace_id, :uuid, null: true

      String :service, null: false                  # e.g. "Events::Update"
      String :subject_type, null: true              # e.g. "event"
      column :subject_id, :uuid, null: true

      audit_outcome :outcome, null: false           # success | denied | error
      String :error_code, null: true                # ServiceError#code on failure
      String :error_message, null: true, text: true

      jsonb :action_params, null: false, default: Sequel.pg_jsonb({})

      # Cross-feature linkage to the idempotency layer and per-request tracing.
      # Both nullable: not every audited call comes from an HTTP request and
      # not every request carries an Idempotency-Key. Schema matches
      # idempotency_keys.idempotency_key_hash so they can join cleanly.
      String :idempotency_key_hash, null: true, fixed: true, size: 64
      String :request_id, null: true

      DateTime :created_at, null: false

      # Bare created_at index supports the retention DELETE without forcing
      # a seq scan — none of the partial indexes above cover rows that have
      # NULL workspace/actor/subject (e.g. system-actor calls).
      index :created_at
    end

    # Hot read paths: "what did this user do", "what happened in this workspace",
    # "who touched this subject". All are time-ordered descending.
    run "CREATE INDEX audit_log_entries_workspace_idx ON audit_log_entries (workspace_id, created_at DESC) WHERE workspace_id IS NOT NULL"
    run "CREATE INDEX audit_log_entries_actor_idx ON audit_log_entries (actor_user_id, created_at DESC) WHERE actor_user_id IS NOT NULL"
    run "CREATE INDEX audit_log_entries_subject_idx ON audit_log_entries (subject_type, subject_id, created_at DESC) WHERE subject_id IS NOT NULL"
  end

  down do
    extension :pg_enum

    drop_table(:audit_log_entries)
    drop_enum(:audit_outcome)
  end
end
