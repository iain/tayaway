# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    # KEY ROTATION CAVEAT: if APP_SECRET changes after this migration has run,
    # all existing encrypted IBANs become unrecoverable without re-encryption
    # using the old key first. Never rotate APP_SECRET without a dedicated
    # re-encryption migration.

    # Encrypt all existing plaintext IBANs
    DB[:users].where(Sequel.negate(iban: nil)).each do |row|
      iban = row[:iban]
      next if iban.nil?

      # Skip already-encrypted values (idempotent re-run safety)
      next if Encryption.encrypted?(iban)

      encrypted = Encryption.encrypt(iban)
      DB[:users].where(id: row[:id]).update(iban: encrypted)
    end
  end

  down do
    # Decrypt all encrypted IBANs back to plaintext
    DB[:users].where(Sequel.negate(iban: nil)).each do |row|
      iban = row[:iban]
      next if iban.nil?
      next unless Encryption.encrypted?(iban)

      decrypted = Encryption.decrypt(iban)
      DB[:users].where(id: row[:id]).update(iban: decrypted)
    end
  end
end
