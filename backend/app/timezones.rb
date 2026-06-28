# frozen_string_literal: true

require "tzinfo"

# Timezone helpers: validating IANA identifiers and turning a civil date plus a
# wall-clock time in a named zone into an absolute instant. The single source
# of truth for how the app reads "18:00 on 2026-06-15 in Europe/Amsterdam" as a
# UTC moment — DST and all.
module Timezones
  # The deployment's home zone. Workspaces default here, events fall back to it
  # when a location yields no zone, and the column defaults match it so inserts
  # from old code still serving traffic during a deploy stay valid.
  DEFAULT = "Europe/Amsterdam"

  class << self
    # True when `name` is a known IANA identifier (e.g. "Europe/Amsterdam").
    def valid?(name)
      return false if name.nil? || name.empty?

      TZInfo::Timezone.get(name)
      true
    rescue TZInfo::InvalidTimezoneIdentifier
      false
    end

    # Resolve a wall-clock time in `zone` to an absolute UTC Time.
    #
    # `date` is a Date; `hour`/`min` are the chore's wall-clock fields. Two DST
    # edges need a policy, so a reminder is always schedulable:
    # - autumn fall-back makes a wall-clock time ambiguous (it happens twice) —
    #   take the earlier instant.
    # - spring-forward gap makes one not exist — push past the gap (every real
    #   DST gap is at most an hour) and resolve that, i.e. 02:30 -> 03:30.
    def resolve(date:, hour:, min:, zone:)
      tz = TZInfo::Timezone.get(zone)
      local = Time.utc(date.year, date.month, date.day, hour, min, 0)
      tz.local_to_utc(local) { |periods| periods.first }
    rescue TZInfo::PeriodNotFound
      tz.local_to_utc(local + 3600) { |periods| periods.first }
    end
  end
end
