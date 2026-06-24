# frozen_string_literal: true

module ChoreRosters
  # Shared parsing for a chore's optional wall-clock reminder time. A blank
  # value means "no time"; anything else must be a 24-hour "HH:MM" string.
  module ChoreTime
    FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

    class << self
      # @return [Result] Success(nil) for blank, Success("HH:MM") when valid,
      #   Failure(ServiceError) otherwise.
      def normalize(time)
        if time.nil? || time.empty?
          Success(nil)
        elsif time.match?(FORMAT)
          Success(time)
        else
          Failure(ServiceError.validation("Time must be a 24-hour time like 09:30"))
        end
      end
    end
  end
end
