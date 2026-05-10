# frozen_string_literal: true

module DatePolls
  # Service to create a date poll for an event.
  module Create
    class << self
      def call(event_id:, membership:, deadline:)
        Auditable.around(
          service: "DatePolls::Create",
          actor: membership,
          subject_type: "date_poll"
        ) do
          Success()
            .bind { Event.find_result(event_id) }
            .bind { |event| EventPolicy.enforce(:create_poll, event, membership: membership) }
            .bind { |event| validate_no_existing_poll(event) }
            .bind { |event| validate_deadline(deadline, event) }
            .bind { |(event, parsed_deadline)| create_poll(event, parsed_deadline, membership) }
        end
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

      def create_poll(event, deadline, membership)
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

        # Opening a poll is the moment an undated event becomes real to
        # the rest of the workspace — that's when they should hear about
        # it. Events::Create stays silent for undated events for exactly
        # this reason.
        Events::AnnounceCreated.call(event: event, actor_user_id: membership.user_id)

        pool = PoolSerializer.new(membership: membership)
        pool.add(:event, [Event.find(event.id)])
        pool.add(:date_poll, [DatePoll.find(poll_id)])
        Success({ objects: pool.to_a })
      end
    end
  end
end
