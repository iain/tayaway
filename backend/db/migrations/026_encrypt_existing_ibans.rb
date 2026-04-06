# frozen_string_literal: true

# Existing plaintext IBANs are encrypted lazily by the application layer:
# - User.from_row handles both plaintext and encrypted values via decrypt_iban
# - Users::UpdateProfile encrypts on write
# No bulk migration needed — IBANs encrypt on next profile save.

Sequel.migration do
  up do
    # Intentional no-op. See comment above.
  end

  down do
    # Nothing to reverse.
  end
end
