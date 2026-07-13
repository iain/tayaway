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

      # The chores whose wall-clock time has already arrived today in `zone`.
      # Today's occurrence of these is history — whoever is on it did (or is
      # doing) the chore — so autofill and clear-unpinned leave those rows
      # alone, exactly like a past day. Untimed chores never match: with no
      # moment to compare, they stay rewritable until the day itself is over.
      def started_today(chores, zone)
        now = Timezones.now(zone)
        now_minutes = (now.hour * 60) + now.min
        chores.select { |c| c.time && ((c.time.hour * 60) + c.time.min) <= now_minutes }
      end
    end
  end
end
