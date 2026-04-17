# frozen_string_literal: true

module Expenses
  # Service to create a new expense on an event.
  module Create
    FACTOR_MIN = 0.5
    FACTOR_MAX = 9.5
    FACTOR_STEP = 0.5
    FACTOR_ERROR = "Participant factor must be a multiple of 0.5 between 0.5 and 9.5"

    class << self
      include Dry::Monads[:result]

      def call(event_id:, membership:, workspace_id:, description:, amount:, start_date:, end_date:,
               id: nil, participant_ids: nil, participants: nil)
        Event.find_result(event_id)
             .bind { |event| EventPolicy.enforce(:create_expense, event, membership: membership) }
             .bind { validate(description, amount, start_date, end_date) }
             .bind { |valid| validate_date_range(valid, event_id) }
             .bind { |valid| validate_rsvp(valid, event_id, membership.user_id) }
             .bind { |valid| validate_participants(valid, participants, participant_ids) }
             .bind { |valid| create_expense(event_id, membership, workspace_id, valid, id) }
      end

      private

      def validate(description, amount, start_date, end_date)
        if description.nil? || description.empty?
          return Failure(ServiceError.validation("Description is required"))
        end

        if description.length > ValidationLimits::SHORT_STRING
          return Failure(ServiceError.validation("Description is too long (maximum 255 characters)"))
        end

        if amount.nil? || amount <= 0
          return Failure(ServiceError.validation("Amount must be greater than zero"))
        end

        if amount > ValidationLimits::EXPENSE_AMOUNT_MAX
          return Failure(ServiceError.validation("Amount cannot exceed 1,000,000"))
        end

        if start_date.nil? || start_date.empty? || end_date.nil? || end_date.empty?
          return Failure(ServiceError.validation("Start date and end date are required"))
        end

        parsed_start, parsed_end = begin
          [Date.strptime(start_date, "%Y-%m-%d"), Date.strptime(end_date, "%Y-%m-%d")]
        rescue Date::Error
          return Failure(ServiceError.validation("Dates must be in YYYY-MM-DD format"))
        end

        if parsed_start > parsed_end
          return Failure(ServiceError.validation("Start date must be on or before end date"))
        end

        Success({ description: description, amount: amount, start_date: parsed_start, end_date: parsed_end })
      end

      def validate_date_range(valid, event_id)
        event = Event.find(event_id)
        if event&.start_date && event.end_date
          if valid[:start_date] < event.start_date || valid[:end_date] > event.end_date
            return Failure(ServiceError.validation("Expense dates must fall within event date range"))
          end
        end

        Success(valid)
      end

      def validate_rsvp(valid, event_id, user_id)
        rsvp = Rsvp.find_by_event_and_user(event_id, user_id)

        if rsvp.nil? || !rsvp.attending
          return Failure(ServiceError.forbidden("You must RSVP to this event before adding expenses"))
        end

        Success(valid)
      end

      def validate_participants(valid, participants, participant_ids)
        normalized = normalize_participants(participants, participant_ids)

        if normalized.nil? || normalized.empty?
          valid[:participants] = []
          return Success(valid)
        end

        user_ids = normalized.map { |p| p[:user_id] }
        if user_ids.uniq.length != user_ids.length
          return Failure(ServiceError.validation("Participants must be unique"))
        end

        existing_count = DB[:users].where(id: user_ids).count
        if existing_count != user_ids.length
          return Failure(ServiceError.validation("One or more participant user IDs are invalid"))
        end

        normalized.each do |p|
          unless valid_factor?(p[:factor])
            return Failure(ServiceError.validation(FACTOR_ERROR))
          end
        end

        valid[:participants] = normalized
        Success(valid)
      end

      def normalize_participants(participants, participant_ids)
        return nil if (participants.nil? || participants.empty?) && (participant_ids.nil? || participant_ids.empty?)

        source = if participants && !participants.empty?
                   participants.map do |p|
                     { user_id: (p[:user_id] || p["user_id"]).to_s, factor: (p[:factor] || p["factor"] || 1.0).to_f }
                   end
                 else
                   participant_ids.map { |uid| { user_id: uid.to_s, factor: 1.0 } }
                 end

        source
      end

      def valid_factor?(factor)
        return false unless factor.is_a?(Numeric)
        return false if factor < FACTOR_MIN - 1e-9 || factor > FACTOR_MAX + 1e-9

        steps = factor / FACTOR_STEP
        (steps - steps.round).abs < 1e-6
      end

      def create_expense(event_id, membership, workspace_id, valid, id)
        # Idempotent replay: if client provided an ID and it already exists, return it
        if id
          existing = Expense.find(id)
          if existing
            pool = PoolSerializer.new(membership: membership)
            pool.add(:expense, [existing])
            return Success({ objects: pool.to_a })
          end
        end

        expense = begin
          DB.transaction do
            now = Time.now
            expense_id = id || SecureRandom.uuid

            DB[:expenses].insert(
              id: expense_id,
              event_id: event_id,
              user_id: membership.user_id,
              amount: valid[:amount],
              description: valid[:description],
              start_date: valid[:start_date],
              end_date: valid[:end_date],
              created_at: now,
              updated_at: now
            )

            insert_participants(expense_id, valid[:participants], workspace_id)

            Broadcaster.object_changed("expense", expense_id, workspace_id: workspace_id)

            Expense.find(expense_id)
          end
        rescue Sequel::UniqueConstraintViolation
          Expense.find(id)
        end

        pool = PoolSerializer.new(membership: membership)
        pool.add(:expense, [expense])

        Success({ objects: pool.to_a })
      end

      def insert_participants(expense_id, participants, workspace_id)
        return if participants.nil? || participants.empty?

        now = Time.now
        participants.each do |p|
          participant_id = SecureRandom.uuid
          DB[:expense_participants].insert(
            id: participant_id,
            expense_id: expense_id,
            user_id: p[:user_id],
            factor: p[:factor],
            created_at: now,
            updated_at: now
          )
          Broadcaster.object_changed("expense_participant", participant_id, workspace_id: workspace_id)
        end
      end
    end
  end
end
