# frozen_string_literal: true

module Events
  # Service to update an existing event.
  #
  # @example
  #   result = Events::Update.call(
  #     event_id: "uuid",
  #     current_user_id: "uuid",
  #     name: "Updated Name",
  #     description: "Updated description"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { objects: [...] }
  module Update
    class << self
      include Events::Validators

      def call(event_id:, membership:, name:, description:, start_date: nil, end_date: nil,
               location_name: nil, latitude: nil, longitude: nil, timezone: nil)
        Auditable.around(
          service: "Events::Update",
          actor: membership,
          subject_type: "event",
          subject_id: event_id,
          context: { name: name }
        ) do
          Success()
            .bind { Event.find_result(event_id) }
            .bind { |event| EventPolicy.enforce(:edit, event, membership: membership) }
            .bind { |event| validate_name_with_event(name, event) }
            .bind { |event| validate_text_lengths(description, location_name).fmap { event } }
            .bind { |event| validate_coordinates(latitude, longitude).fmap { event } }
            .bind { |event| validate_timezone(timezone).fmap { event } }
            .bind { |event| validate_dates(start_date, end_date).fmap { |dates| [event, dates] } }
            .bind { |(event, dates)| check_no_resolved_poll_when_clearing(event, dates).fmap { [event, dates] } }
            .bind do |(event, dates)|
              update_event(
                event: event, membership: membership, name: name, description: description, dates: dates,
                location_name: location_name, latitude: latitude, longitude: longitude, timezone: timezone
              )
            end
        end
      end

      private

      def validate_name_with_event(name, event)
        if name.nil? || name.empty?
          Failure(ServiceError.validation("Name is required"))
        elsif name.length > ValidationLimits::SHORT_STRING
          Failure(ServiceError.validation("Name is too long (maximum 255 characters)"))
        else
          Success(event)
        end
      end

      def validate_dates(start_date, end_date)
        return Success(nil) if start_date.nil? && end_date.nil?

        # Both empty string — clear dates
        if (start_date.nil? || start_date.empty?) && (end_date.nil? || end_date.empty?)
          return Success([])
        end

        if start_date.nil? || start_date.empty? || end_date.nil? || end_date.empty?
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

      def check_no_resolved_poll_when_clearing(event, dates)
        return Success(nil) unless dates && dates.empty?

        poll = DatePoll.find_by_event(event.id)
        if poll&.closed_at
          Failure(ServiceError.validation("Cannot clear dates while a resolved poll exists"))
        else
          Success(nil)
        end
      end

      def update_event(event:, membership:, name:, description:, dates:, location_name:, latitude:, longitude:, timezone:)
        event_id = event.id
        workspace_id = event.workspace_id
        before = event

        DB.transaction do
          update_data = {
            name: name,
            description: description && description.empty? ? nil : description,
            updated_at: Time.now
          }

          # Blank means "no change"; a new zone is honoured as sent (the client
          # re-derives it from a changed location, or the user overrode it).
          if timezone && !timezone.empty?
            update_data[:timezone] = timezone
          end

          if dates
            if dates.empty?
              update_data[:start_date] = nil
              update_data[:end_date] = nil
            else
              update_data[:start_date] = dates[0]
              update_data[:end_date] = dates[1]
            end
          end

          unless location_name.nil?
            if location_name.empty?
              update_data[:location_name] = nil
              update_data[:location_coordinates] = nil
            elsif latitude && longitude
              update_data[:location_name] = location_name
              update_data[:location_coordinates] = Sequel.lit("point(?, ?)", longitude, latitude)
            else
              update_data[:location_name] = location_name
              update_data[:location_coordinates] = nil
            end
          end

          DB[:events].where(id: event_id).update(update_data)

          Broadcaster.object_changed("event", event_id)
        end

        APP_LOGGER.info { "[Events::Update] Event #{event_id} updated in workspace #{workspace_id}" }

        after = Event.find(event_id)
        Events::OnDetailsChanged.call(before: before, after: after, actor_user_id: membership.user_id) if after

        # A changed zone moves every chore reminder for this event. Isolated
        # like other notification work so a scheduling hiccup can't undo the
        # saved edit.
        if after && before.timezone != after.timezone
          Notifications::Safely.deliver(context: "Events::Update#reschedule_reminders") do
            ChoreRosters::ScheduleReminder.reschedule_for_event(after)
          end
        end

        pool = PoolSerializer.new(membership: membership)
        pool.add(:event, [after]) if after
        Success({ objects: pool.to_a })
      end
    end
  end
end
