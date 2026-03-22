# Migration Safety Guide

Migrations run during `deploy:updated`, **before** the app restarts. This means the
old version of the code is still serving live traffic when the migration executes.

Destructive schema changes (dropping columns, adding NOT NULL constraints, renaming)
will break the running old code. All migrations must be **additive**.

## The Golden Rule

> A migration must not remove or constrain anything that old code depends on.

## Safe operations (additive)

These are safe to run while old code is serving traffic:

- Adding a nullable column
- Adding a new table
- Adding an index (use `CONCURRENTLY` for large tables — but note RuboCop's
  `Sequel/ConcurrentIndex` cop; disable it with a rubocop comment in migrations)
- Backfilling data in new nullable columns
- Adding a foreign key with `ON DELETE SET NULL` or `ON DELETE CASCADE`
- Adding a column with a default value

## Unsafe operations (destructive)

These break old code if done in a single deploy:

| Operation | Why it breaks |
| --- | --- |
| `drop_column` | Old code still tries to read/write the column |
| `set_column_not_null` on existing rows | Old code may insert rows without the column |
| `rename_column` / `rename_table` | Old code references the old name |
| `drop_table` | Old code still queries the table |
| Adding a NOT NULL column without a default | INSERT from old code will fail |

## Two-Deploy Pattern for Destructive Changes

When you need to remove or constrain something, split it across two deploys.

**Deploy 1 — Remove from code, keep in DB:**
- Stop reading/writing the column in application code
- Do not write a migration yet

**Deploy 2 — Remove from DB:**
- Write a migration to drop the column/table
- Old code no longer references it, so the migration is safe

### Example: Dropping a column

**Deploy 1 migration** — none needed. Just remove references from code.

**Deploy 2 migration:**

```ruby
Sequel.migration do
  up do
    alter_table(:events) do
      drop_column :legacy_field
    end
  end

  down do
    alter_table(:events) do
      add_column :legacy_field, :text
    end
  end
end
```

### Example: Adding a NOT NULL column

**Deploy 1 migration** — add as nullable:

```ruby
Sequel.migration do
  up do
    alter_table(:events) do
      add_column :status, :text  # nullable — safe while old code runs
    end
  end

  down do
    alter_table(:events) do
      drop_column :status
    end
  end
end
```

**Then backfill** (can be in the same migration or a separate one):

```ruby
run "UPDATE events SET status = 'active' WHERE status IS NULL"
```

**Deploy 2 migration** — add the constraint once code always sets the value:

```ruby
Sequel.migration do
  up do
    alter_table(:events) do
      set_column_not_null :status
    end
  end

  down do
    alter_table(:events) do
      set_column_allow_null :status
    end
  end
end
```

## Within-Migration Safety (Single Deploy)

If a migration needs to add a column and then constrain it (all in one deploy), it is
only safe if the backfill and constraint are applied atomically — i.e., the column is
brand new with no existing rows, or all existing rows are backfilled before the
constraint is added. Migration `002_add_date_polls.rb` demonstrates this pattern:

1. Add `date_poll_id` as nullable
2. Backfill all existing rows via SQL
3. Set `NOT NULL` and add the foreign key

This is safe because steps 1-3 happen in sequence within a single migration transaction,
and no old-code traffic can insert rows with a missing `date_poll_id` in between (the
column is new and the old code path doesn't know about it).

## PR Checklist for Migrations

Before merging a PR that includes a migration, verify:

- [ ] No `drop_column`, `drop_table`, or `rename_column`/`rename_table` unless this is
      Deploy 2 of a two-deploy sequence
- [ ] No `set_column_not_null` on a column that old code might not populate
- [ ] New NOT NULL columns have a `default:` value or are populated entirely in the
      same migration before the constraint is applied
- [ ] Indexes on large tables use `CONCURRENTLY` (with the rubocop disable comment)
