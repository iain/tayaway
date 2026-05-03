# frozen_string_literal: true

# The name on someone's bank account is often not the same as their display
# name in the app, and EPC QR codes need the bank-account name for the
# transfer to actually arrive at the right account. Stored encrypted alongside
# the IBAN itself.
Sequel.migration do
  change do
    alter_table(:users) do
      add_column :iban_holder_name, :text
    end
  end
end
