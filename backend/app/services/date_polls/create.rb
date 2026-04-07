# frozen_string_literal: true

module DatePolls
  # Service to create a date poll for an event.
  module Create
    class << self
      include Dry::Monads[:result]

      def call(event_id:, current_user_id:, deadline:)
        Event.find_result(event_id)
             .bind { |event| Event.authorize_owner(event, current_user_id) }
             .bind { |event| validate_no_existing_poll(event) }
             .bind { |event| validate_deadline(deadline, event) }
             .bind { |(event, parsed_deadline)| create_poll(event, parsed_deadline) }
      end

      private

      def validate_no_existing_poll(event)
        existing = DatePoll.find_by_event(event.id)
        if existing
          Failure(ServiceError.conflict("A date poll already exists for this event"))
        else
          Success(event)
        end
      end

      def validate_deadline(deadline, event)
        if deadline.nil? || deadline.empty?
          return Failure(ServiceError.validation("Deadline is required"))
        end

        begin
          parsed = Time.parse(deadline)
        rescue ArgumentError
          return Failure(ServiceError.validation("Invalid deadline format"))
        end

        if parsed <= Time.now
          return Failure(ServiceError.validation("Deadline must be in the future"))
        end

        Success([event, parsed])
      end

      def create_poll(event, deadline)
        poll_id = SecureRandom.uuid
        now = Time.now

        DB.transaction do
          DB[:date_polls].insert(
            id: poll_id,
            event_id: event.id,
            deadline: deadline,
            created_at: now,
            updated_at: now
          )

          Broadcaster.object_changed("date_poll", poll_id, workspace_id: event.workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: event.workspace_id)
        pool.add_event(Event.find(event.id))
        pool.add_date_poll(DatePoll.find(poll_id))
        Success({ objects: pool.to_a })
      end
    end
  end
end
