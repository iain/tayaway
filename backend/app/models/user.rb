# frozen_string_literal: true

# Read-only user model.
class User
  attr_reader :id, :email, :name, :phone_number, :birthday, :location_name, :location_coordinates, :iban, :created_at, :updated_at

  def initialize(
    id:,
    email:,
    name:,
    phone_number:,
    birthday:,
    location_name:,
    location_coordinates:,
    iban:,
    created_at:,
    updated_at:
  )
    @id = id
    @email = email
    @name = name
    @phone_number = phone_number
    @birthday = birthday
    @location_name = location_name
    @location_coordinates = location_coordinates
    @iban = iban
    @created_at = created_at
    @updated_at = updated_at
  end

  # Serializes the user for API responses. IBAN is deliberately excluded —
  # it must only appear (masked) in the authenticated /api/auth/me response.
  # All other consumers (PoolSerializer, broadcasts) build their own hashes
  # and expose only `hasIban: true/false`.
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

    def decrypt_field(value)
      return nil if value.nil?
      return value unless Encryption.encrypted?(value)

      Encryption.decrypt(value)
    end

    def dataset
      DB[:users].with_row_proc(method(:from_row))
    end

    def from_row(row)
      phone = decrypt_field(row[:phone_number])

      # Birthday is stored as DATE (plaintext) or encrypted STRING.
      # Decrypt if encrypted, then parse to Date.
      raw_birthday = row[:birthday]
      birthday = if raw_birthday.is_a?(Date)
                   raw_birthday
                 elsif raw_birthday.is_a?(String) && Encryption.encrypted?(raw_birthday)
                   Date.parse(Encryption.decrypt(raw_birthday))
                 elsif raw_birthday.is_a?(String)
                   Date.parse(raw_birthday)
                 end

      User.new(
        id: UUID.new(row[:id]),
        email: EmailAddress.new(row[:email]),
        name: row[:name],
        phone_number: phone,
        birthday: birthday,
        location_name: row[:location_name],
        location_coordinates: PointParser.parse(row[:location_coordinates]),
        iban: decrypt_field(row[:iban]),
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
