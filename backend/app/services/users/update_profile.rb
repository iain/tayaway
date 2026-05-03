# frozen_string_literal: true

module Users
  # Service to update a user's profile (name and contact fields).
  #
  # @example
  #   result = Users::UpdateProfile.call(
  #     user_id: "uuid",
  #     current_user_id: "uuid",
  #     name: "New Name",
  #     phone_number: "+1234567890",
  #     birthday: "1990-01-15",
  #     location_name: "Berlin, Germany",
  #     latitude: 52.52,
  #     longitude: 13.405
  #   )
  #   result.success?  # => true
  #   result.value!    # => { objects: [...] }
  module UpdateProfile
    class << self
      def call(user_id:, current_user_id:, name:, phone_number: nil, birthday: nil,
               location_name: nil, latitude: nil, longitude: nil, iban: nil, iban_holder_name: nil)
        Auditable.around(
          service: "Users::UpdateProfile",
          actor: nil,
          actor_user_id: current_user_id,
          subject_type: "user",
          subject_id: user_id,
          context: { name: name }
        ) do
          Success()
            .bind { find_user(user_id) }
            .bind { |user| authorize(user, current_user_id) }
            .bind { |user| validate_name(name, user) }
            .bind { |user| validate_birthday(birthday, user) }
            .bind { |user| validate_coordinates(latitude, longitude, user) }
            .bind { |user| validate_iban(iban, user) }
            .bind { |user| validate_text_lengths(phone_number, location_name, iban_holder_name, user) }
            .bind { |user| update_profile(user, name, phone_number, birthday, location_name, latitude, longitude, iban, iban_holder_name) }
        end
      end

      private

      def find_user(user_id)
        user = User.find(user_id)
        if user
          Success(user)
        else
          Failure(ServiceError.not_found("User not found"))
        end
      end

      def authorize(user, current_user_id)
        if user.id == current_user_id
          Success(user)
        else
          Failure(ServiceError.forbidden("Access denied"))
        end
      end

      def validate_name(name, user)
        # nil means "don't change" — skip validation
        return Success(user) if name.nil?

        if name.strip.empty?
          Failure(ServiceError.validation("Name is required"))
        elsif name.length > ValidationLimits::SHORT_STRING
          Failure(ServiceError.validation("Name is too long (maximum #{ValidationLimits::SHORT_STRING} characters)"))
        else
          Success(user)
        end
      end

      def validate_birthday(birthday, user)
        if birthday && !birthday.empty?
          parsed = Date.parse(birthday)
          if parsed < ValidationLimits::BIRTHDAY_MIN
            return Failure(ServiceError.validation("Birthday is too far in the past"))
          end
          if parsed > Date.today
            return Failure(ServiceError.validation("Birthday cannot be in the future"))
          end
        end
        Success(user)
      rescue Date::Error
        Failure(ServiceError.validation("Invalid birthday format"))
      end

      def validate_coordinates(latitude, longitude, user)
        if latitude && !ValidationLimits::LATITUDE_RANGE.cover?(latitude)
          return Failure(ServiceError.validation("Latitude must be between -90 and 90"))
        end

        if longitude && !ValidationLimits::LONGITUDE_RANGE.cover?(longitude)
          return Failure(ServiceError.validation("Longitude must be between -180 and 180"))
        end

        Success(user)
      end

      def validate_iban(iban, user)
        # nil means "don't change", empty means "clear"
        return Success(user) if iban.nil? || iban.strip.empty?

        normalized = iban.gsub(/\s/, "").upcase
        unless normalized.match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{4,30}\z/)
          return Failure(ServiceError.validation("Invalid IBAN format"))
        end

        # MOD97-10 checksum validation
        rearranged = normalized[4..] + normalized[0..3]
        numeric = rearranged.chars.map { |c| c.match?(/[A-Z]/) ? (c.ord - 55).to_s : c }.join
        unless numeric.to_i % 97 == 1
          return Failure(ServiceError.validation("Invalid IBAN checksum"))
        end

        Success(user)
      end

      def validate_text_lengths(phone_number, location_name, iban_holder_name, user)
        if phone_number && phone_number.length > ValidationLimits::PHONE_NUMBER
          return Failure(ServiceError.validation("Phone number is too long (maximum #{ValidationLimits::PHONE_NUMBER} characters)"))
        end

        if location_name && location_name.length > ValidationLimits::SHORT_STRING
          return Failure(ServiceError.validation("Location name is too long (maximum #{ValidationLimits::SHORT_STRING} characters)"))
        end

        # 70 chars matches the EPC QR specification's recipient-name cap, so a
        # name we accept here also fits in the QR payload without truncation.
        if iban_holder_name && iban_holder_name.length > 70
          return Failure(ServiceError.validation("Name on bank account is too long (maximum 70 characters)"))
        end

        Success(user)
      end

      def update_profile(user, name, phone_number, birthday, location_name, latitude, longitude, iban, iban_holder_name)
        user_id = user.id

        DB.transaction do
          update_data = {
            updated_at: Time.now
          }

          # Name: nil means "don't change"
          update_data[:name] = name.strip unless name.nil?

          # Phone number: blank -> nil, otherwise encrypt
          unless phone_number.nil?
            stripped = phone_number.strip
            update_data[:phone_number] = stripped.empty? ? nil : Encryption.encrypt(stripped, user_id: user_id)
          end

          # Birthday: blank -> nil, otherwise encrypt (stored as encrypted ISO 8601 string)
          unless birthday.nil?
            stripped = birthday.strip
            update_data[:birthday] = stripped.empty? ? nil : Encryption.encrypt(stripped, user_id: user_id)
          end

          # IBAN: blank -> nil, otherwise normalize and encrypt
          unless iban.nil?
            normalized = iban.strip.empty? ? nil : iban.gsub(/\s/, "").upcase
            update_data[:iban] = normalized ? Encryption.encrypt(normalized, user_id: user_id) : nil
          end

          # IBAN holder name: blank -> nil, otherwise encrypt
          unless iban_holder_name.nil?
            stripped = iban_holder_name.strip
            update_data[:iban_holder_name] = stripped.empty? ? nil : Encryption.encrypt(stripped, user_id: user_id)
          end

          # Location: blank -> clear both, otherwise set both
          unless location_name.nil?
            if location_name.strip.empty?
              update_data[:location_name] = nil
              update_data[:location_coordinates] = nil
            elsif latitude && longitude
              update_data[:location_name] = location_name.strip
              update_data[:location_coordinates] = Sequel.lit("point(?, ?)", longitude, latitude)
            end
          end

          DB[:users].where(id: user_id.to_s).update(update_data)

          # Broadcast member changes to all workspaces the user belongs to
          WorkspaceMembership.for_user(user_id).each do |m|
            Broadcaster.object_changed("member", m.id, workspace_id: m.workspace_id)
          end
        end

        APP_LOGGER.info { "[Users::UpdateProfile] User #{user_id} updated their profile" }

        # Build pool with member objects for each workspace membership
        memberships = WorkspaceMembership.for_user(user_id)

        pool = PoolSerializer.new
        pool.add(:member, memberships)

        Success({ objects: pool.to_a })
      end
    end
  end
end
