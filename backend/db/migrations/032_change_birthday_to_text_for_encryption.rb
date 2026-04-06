# frozen_string_literal: true

# Change birthday from DATE to TEXT so it can store encrypted ciphertext.
# Existing DATE values are cast to TEXT (ISO 8601 format) automatically by PostgreSQL.
# No app code needed — the User model handles both plaintext and encrypted values on read.
Sequel.migration do
  up do
    alter_table(:users) do
      set_column_type :birthday, :text, using: Sequel.lit("birthday::text")
    end
  end

  down do
    alter_table(:users) do
      set_column_type :birthday, :date, using: Sequel.lit("birthday::date")
    end
  end
end
