# typed: true
# frozen_string_literal: true

module Events
  # Service to update an existing event.
  #
  # @example
  #   result = Events::Update.call(
  #     event: event,
  #     current_user_id: "uuid",
  #     name: "Updated Name",
  #     description: "Updated description",
  #     date_ranges: [{ "start_date" => "2024-01-01", "end_date" => "2024-01-02" }]
  #   )
  #   result.success?  # => true
  #   result.value!    # => { event: {...} }
  module Update
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event: Event,
          current_user_id: String,
          name: T.nilable(String),
          description: T.nilable(String),
          date_ranges: T::Array[T::Hash[String, String]]
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event:, current_user_id:, name:, description:, date_ranges:)
        authorize_owner(event, current_user_id)
          .bind { validate_name(name) }
          .bind { |valid_name| update_event(event, valid_name, description, date_ranges) }
      end

      private

      sig { params(event: Event, current_user_id: String).returns(Result[Event, ServiceError]) }
      def authorize_owner(event, current_user_id)
        if event.user_id == current_user_id
          Success(event)
        else
          Failure(ServiceError.forbidden("Access denied"))
        end
      end

      sig { params(name: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_name(name)
        if name.nil? || name.empty?
          Failure(ServiceError.validation("Name is required"))
        else
          Success(name)
        end
      end

      sig do
        params(
          event: Event,
          name: String,
          description: T.nilable(String),
          date_ranges: T::Array[T::Hash[String, String]]
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_event(event, name, description, date_ranges)
        updated_event = DB.transaction do
          event.update(
            name: name,
            description: description&.empty? ? nil : description
          )

          sync_date_ranges(event, date_ranges)

          event.reload
        end

        Success({ event: updated_event.to_api_hash })
      end

      sig do
        params(
          event: Event,
          date_ranges: T::Array[T::Hash[String, String]]
        ).void
      end
      def sync_date_ranges(event, date_ranges)
        incoming = date_ranges.map do |dr|
          [Date.parse(dr["start_date"]), Date.parse(dr["end_date"])]
        end.to_set

        existing = event.date_ranges.map do |dr|
          [[dr.start_date, dr.end_date], dr]
        end.to_h

        # Delete date ranges that are no longer in the incoming list
        existing.each do |(key, dr)|
          dr.delete unless incoming.include?(key)
        end

        # Create new date ranges that don't exist yet
        existing_keys = existing.keys.to_set
        incoming.each do |(start_date, end_date)|
          next if existing_keys.include?([start_date, end_date])

          DateRange.create(
            event_id: event.id,
            start_date: start_date,
            end_date: end_date
          )
        end
      end
    end
  end
end
