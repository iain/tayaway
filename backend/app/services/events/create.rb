# frozen_string_literal: true

module Events
  # Service to create a new event.
  #
  # @example
  #   result = Events::Create.call(
  #     membership: membership,
  #     name: "Team Meeting",
  #     description: "Weekly sync"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { objects: [...] }
  module Create
    class << self
      include Dry::Monads[:result]
      include Events::Validators

      def call(workspace_id:, membership:, name:, description:, id: nil, start_date: nil, end_date: nil,
               location_name: nil, latitude: nil, longitude: nil)
        Auditable.around(
          service: "Events::Create",
          actor: membership,
          subject_type: "event",
          workspace_id: workspace_id,
          context: { name: name }
        ) do
          Success()
            .bind { Workspace.find_result(workspace_id) }
            .bind { |workspace| WorkspacePolicy.enforce(:create_event, workspace, membership: membership) }
            .bind { validate_name(name) }
            .bind { |valid_name| validate_text_lengths(description, location_name).fmap { valid_name } }
            .bind { |valid_name| validate_coordinates(latitude, longitude).fmap { valid_name } }
            .bind { |valid_name| validate_dates(start_date, end_date).fmap { |dates| [valid_name, dates] } }
            .bind do |(valid_name, dates)|
              create_event(
                workspace_id: workspace_id, membership: membership, name: valid_name,
                description: description, id: id, dates: dates,
                location_name: location_name, latitude: latitude, longitude: longitude
              )
            end
        end
      end

      private

      def validate_name(name)
        if name.nil? || name.empty?
          Failure(ServiceError.validation("Name is required"))
        elsif name.length > ValidationLimits::SHORT_STRING
          Failure(ServiceError.validation("Name is too long (maximum 255 characters)"))
        else
          Success(name)
        end
      end

      def validate_dates(start_date, end_date)
        return Success(nil) if start_date.nil? && end_date.nil?

        if start_date.nil? || end_date.nil?
          return Failure(ServiceError.validation("Both start date and end date must be provided"))
        end

        parsed_start = Date.parse(start_date)
        parsed_end = Date.parse(end_date)

        if parsed_start > parsed_end
          return Failure(ServiceError.validation("Start date must be before or equal to end date"))
        end

        Success([parsed_start, parsed_end])
      rescue Date::Error
        Failure(ServiceError.validation("Invalid date format"))
      end

      def create_event(workspace_id:, membership:, name:, description:, id:, dates:, location_name:, latitude:, longitude:)
        now = Time.now
        event_id = id || SecureRandom.uuid

        insert_data = {
          id: event_id,
          workspace_id: workspace_id,
          user_id: membership.user_id,
          name: name,
          description: description&.empty? ? nil : description,
          created_at: now,
          updated_at: now
        }

        if dates
          insert_data[:start_date] = dates[0]
          insert_data[:end_date] = dates[1]
        end

        if location_name && !location_name.empty? && latitude && longitude
          insert_data[:location_name] = location_name
          insert_data[:location_coordinates] = Sequel.lit("point(?, ?)", longitude, latitude)
        end

        inserted = nil
        DB.transaction do
          inserted = DB[:events]
                     .returning(:id)
                     .insert_conflict
                     .insert(insert_data)
                     .first

          Broadcaster.object_changed("event", event_id, workspace_id: workspace_id) if inserted
        end

        event = Event.find(event_id)

        if inserted
          APP_LOGGER.info { "[Events::Create] User #{membership.user_id} created event #{event.id} in workspace #{workspace_id}" }
        end

        pool = PoolSerializer.new(membership: membership)
        pool.add(:event, [event])

        Success({ objects: pool.to_a })
      end
    end
  end
end
