# typed: true
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
      extend T::Sig
      include Result::Methods

      sig do
        params(
          user_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          name: T.nilable(String),
          phone_number: T.nilable(String),
          birthday: T.nilable(String),
          location_name: T.nilable(String),
          latitude: T.nilable(Float),
          longitude: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(user_id:, current_user_id:, name:, phone_number: nil, birthday: nil,
               location_name: nil, latitude: nil, longitude: nil)
        find_user(user_id)
          .bind { |user| authorize(user, current_user_id) }
          .bind { |user| validate_name(name, user) }
          .bind { |user| validate_birthday(birthday, user) }
          .bind { |user| update_profile(user, name, phone_number, birthday, location_name, latitude, longitude) }
      end

      private

      sig { params(user_id: T.any(String, UUID)).returns(Result[User, ServiceError]) }
      def find_user(user_id)
        user = User.find(user_id)
        if user
          T.cast(Success(user), Result[User, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("User not found")), Result[User, ServiceError])
        end
      end

      sig { params(user: User, current_user_id: T.any(String, UUID)).returns(Result[User, ServiceError]) }
      def authorize(user, current_user_id)
        if user.id == current_user_id
          T.cast(Success(user), Result[User, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Access denied")), Result[User, ServiceError])
        end
      end

      sig { params(name: T.nilable(String), user: User).returns(Result[User, ServiceError]) }
      def validate_name(name, user)
        # nil means "don't change" — skip validation
        return T.cast(Success(user), Result[User, ServiceError]) if name.nil?

        if name.strip.empty?
          T.cast(Failure(ServiceError.validation("Name is required")), Result[User, ServiceError])
        else
          T.cast(Success(user), Result[User, ServiceError])
        end
      end

      sig { params(birthday: T.nilable(String), user: User).returns(Result[User, ServiceError]) }
      def validate_birthday(birthday, user)
        if birthday && !birthday.empty?
          Date.parse(birthday)
        end
        T.cast(Success(user), Result[User, ServiceError])
      rescue Date::Error
        T.cast(Failure(ServiceError.validation("Invalid birthday format")), Result[User, ServiceError])
      end

      sig do
        params(
          user: User,
          name: T.nilable(String),
          phone_number: T.nilable(String),
          birthday: T.nilable(String),
          location_name: T.nilable(String),
          latitude: T.nilable(Float),
          longitude: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_profile(user, name, phone_number, birthday, location_name, latitude, longitude)
        user_id = user.id

        DB.transaction do
          update_data = {
            updated_at: Time.now
          }

          # Name: nil means "don't change"
          update_data[:name] = name.strip unless name.nil?

          # Phone number: blank -> nil
          unless phone_number.nil?
            update_data[:phone_number] = phone_number.strip.empty? ? nil : phone_number.strip
          end

          # Birthday: blank -> nil, otherwise parse
          unless birthday.nil?
            update_data[:birthday] = birthday.strip.empty? ? nil : Date.parse(birthday)
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

        # Build pool with member objects for each workspace membership
        memberships = WorkspaceMembership.for_user(user_id)

        pool = PoolSerializer.new
        memberships.each do |m|
          pool.add_member_from_membership(m)
        end

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
