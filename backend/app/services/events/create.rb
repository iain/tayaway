# typed: true
# frozen_string_literal: true

module Events
  # Service to create a new event with optional date ranges.
  #
  # @example
  #   result = Events::Create.call(
  #     user_id: "uuid",
  #     name: "Team Meeting",
  #     description: "Weekly sync",
  #     date_ranges: [{ "start_date" => "2024-01-01", "end_date" => "2024-01-02" }]
  #   )
  #   result.success?  # => true
  #   result.value!    # => { event: {...} }
  module Create
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          user_id: String,
          name: T.nilable(String),
          description: T.nilable(String),
          date_ranges: T::Array[T::Hash[String, String]]
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(user_id:, name:, description:, date_ranges:)
        validate_name(name).bind { |valid_name| create_event(user_id, valid_name, description, date_ranges) }
      end

      private

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
          user_id: String,
          name: String,
          description: T.nilable(String),
          date_ranges: T::Array[T::Hash[String, String]]
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_event(user_id, name, description, date_ranges)
        event = DB.transaction do
          new_event = Event.create(
            user_id: user_id,
            name: name,
            description: description&.empty? ? nil : description
          )

          date_ranges.each do |dr|
            DateRange.create(
              event_id: new_event.id,
              start_date: Date.parse(dr["start_date"]),
              end_date: Date.parse(dr["end_date"])
            )
          end

          new_event.reload
        end

        pool = PoolSerializer.new
        pool.add(event)

        Success({ event: event.to_api_hash, objects: pool.to_a })
      end
    end
  end
end
