# frozen_string_literal: true

# Guests give plus-ones a persistent, workspace-level identity; attendances
# hold one row per person (member or guest) per event. Target model and
# migration staging: doc/attendances.md. Additive — rsvps stay untouched and
# remain the settlement source of truth until the staged cutover.
Sequel.migration do
  up do
    create_table(:guests) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :workspace_id, :workspaces, type: :uuid, null: false, on_delete: :cascade
      column :name, :text, null: false
      # Synthesized by the rsvp plus-ones backfill; hidden from pickers until
      # renamed (renaming clears the flag).
      column :placeholder, TrueClass, null: false, default: false
      # NO ACTION (no on_delete), per the 039 created_by precedent.
      foreign_key :created_by_user_id, :users, type: :uuid, null: true
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")

      index :workspace_id
    end

    run <<~SQL
      CREATE TRIGGER update_guests_updated_at
        BEFORE UPDATE ON guests
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL

    create_table(:attendances) do
      # Client-generated, like rsvps.
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :event_id, :events, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: true, on_delete: :cascade
      # NO ACTION deliberately, not RESTRICT: it checks at statement end, so a
      # workspace delete cascading workspace→guests and workspace→events→
      # attendances in one statement succeeds, while a direct DELETE FROM
      # guests with live references still fails. Direct guest deletion is
      # guarded app-side (GuestPolicy :has_attendances).
      foreign_key :guest_id, :guests, type: :uuid, null: true
      # The member who brings (and is billed for) a guest. Per-event on
      # purpose: the same guest can be brought by different members on
      # different trips. NO ACTION.
      foreign_key :host_user_id, :users, type: :uuid, null: true
      column :status, :text, null: false
      # Flat ["2026-07-01", ...]; NULL = whole event. Only meaningful when
      # status = 'going' — kept NULL otherwise so NULL always reads "whole
      # event", it just isn't read outside going.
      column :days, :jsonb, null: true
      # The actor who filed the row (may differ from the subject). NO ACTION.
      foreign_key :created_by_user_id, :users, type: :uuid, null: true
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")

      constraint(:attendance_subject_xor, Sequel.lit("(user_id IS NOT NULL) <> (guest_id IS NOT NULL)"))
      constraint(:attendance_guest_has_host, Sequel.lit("(guest_id IS NOT NULL AND host_user_id IS NOT NULL) OR (user_id IS NOT NULL AND host_user_id IS NULL)"))
      constraint(:attendance_status, Sequel.lit("status IN ('pending', 'going', 'declined')"))
      constraint(:attendance_days_only_when_going, Sequel.lit("days IS NULL OR status = 'going'"))

      # Partial uniques are the upsert conflict targets (one row per person
      # per event); re-adding a removed guest lands on their existing row.
      index %i[event_id user_id], unique: true, where: Sequel.lit("user_id IS NOT NULL"), name: :attendances_event_user_unique
      index %i[event_id guest_id], unique: true, where: Sequel.lit("guest_id IS NOT NULL"), name: :attendances_event_guest_unique
      index :event_id
      index :guest_id
      index :host_user_id
    end

    run <<~SQL
      CREATE TRIGGER update_attendances_updated_at
        BEFORE UPDATE ON attendances
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:attendances)
    drop_table(:guests)
  end
end
