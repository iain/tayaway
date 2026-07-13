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
      if name.nil? || name.empty?
        false
      else
        TZInfo::Timezone.get(name)
        true
      end
    rescue TZInfo::InvalidTimezoneIdentifier
      false
    end

    # Validity rule for a timezone form field: blank (nil or whitespace-only)
    # means "use the default / leave unchanged", otherwise it must be a known
    # IANA identifier. Stripped before checking so a padded-but-real zone passes
    # — matching how the services persist it (stripped). The single predicate
    # both Events and Users validation share.
    def blank_or_valid?(name)
      name.nil? || name.strip.empty? || valid?(name.strip)
    end

    # The current wall-clock time in `zone` — "now" as someone at the event
    # experiences it, for fences finer than a day (e.g. whether a timed chore
    # has already started today).
    def now(zone)
      TZInfo::Timezone.get(zone).to_local(Time.now)
    end

    # The current civil date in `zone` — "today" as someone at the event
    # experiences it, which is what date fences (e.g. the chore roster's
    # past/upcoming split) must be reckoned against.
    def today(zone)
      now(zone).to_date
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
