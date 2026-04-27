# frozen_string_literal: true

# Read-only user model.
class User < Data.define(:id, :email, :name, :phone_number, :birthday, :location_name, :location_coordinates, :iban, :created_at, :updated_at)
  # Serializes the user for API responses. IBAN is deliberately excluded —
  # it must only appear (masked) in the authenticated /api/auth/me response.
  # The sender of an unpaid transfer can fetch the recipient's full IBAN via
  # the per-transfer payment-details endpoint; no other surface exposes it.
  def to_api_hash
    {
      id: id.to_s,
      objectType: "user",
      email: email.to_s,
      name: name,
      phoneNumber: phone_number,
      birthday: birthday&.iso8601,
      locationName: location_name,
      latitude: location_coordinates&.[](1),
      longitude: location_coordinates&.[](0),
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    def find(id)
      dataset.where(id: id).first
    end

    def find_by_email(email)
      dataset.where(Sequel.lit("LOWER(email) = ?", email.to_s.downcase)).first
    end

    def for_ids(ids)
      return [] if ids.empty?

      dataset.where(id: ids).all
    end

    private

    def decrypt_field(value, user_id:)
      return nil if value.nil?

      Encryption.decrypt(value, user_id: user_id)
    end

    def dataset
      DB[:users].with_row_proc(method(:from_row))
    end

    def from_row(row)
      user_id = row[:id]

      raw_birthday = row[:birthday]
      birthday = raw_birthday ? Date.parse(decrypt_field(raw_birthday, user_id: user_id)) : nil

      new(
        id: UUID.new(user_id),
        email: EmailAddress.new(row[:email]),
        name: row[:name],
        phone_number: decrypt_field(row[:phone_number], user_id: user_id),
        birthday: birthday,
        location_name: row[:location_name],
        location_coordinates: PointParser.parse(row[:location_coordinates]),
        iban: decrypt_field(row[:iban], user_id: user_id),
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
