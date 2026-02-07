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
          workspace_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          name: T.nilable(String),
          description: T.nilable(String),
          date_ranges: T::Array[T::Hash[String, String]]
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(workspace_id:, user_id:, name:, description:, date_ranges:)
        validate_name(name).bind { |valid_name| create_event(workspace_id, user_id, valid_name, description, date_ranges) }
      end

      private

      sig { params(name: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_name(name)
        if name.nil? || name.empty?
          T.cast(Failure(ServiceError.validation("Name is required")), Result[String, ServiceError])
        else
          T.cast(Success(name), Result[String, ServiceError])
        end
      end

      sig do
        params(
          workspace_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          name: String,
          description: T.nilable(String),
          date_ranges: T::Array[T::Hash[String, String]]
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_event(workspace_id, user_id, name, description, date_ranges)
        event = DB.transaction do
          now = Time.now
          event_id = SecureRandom.uuid

          DB[:events].insert(
            id: event_id,
            workspace_id: workspace_id,
            user_id: user_id,
            name: name,
            description: description&.empty? ? nil : description,
            created_at: now,
            updated_at: now
          )

          date_ranges.each do |dr|
            dr_now = Time.now
            DB[:date_ranges].insert(
              id: SecureRandom.uuid,
              event_id: event_id,
              start_date: Date.parse(dr["start_date"]),
              end_date: Date.parse(dr["end_date"]),
              created_at: dr_now,
              updated_at: dr_now
            )
          end

          Broadcaster.object_changed("event", event_id)

          Event.find(event_id)
        end

        pool = PoolSerializer.new
        pool.add_event(event)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
