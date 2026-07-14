# frozen_string_literal: true

module Attendances
  class << self
    # Normalizes a mirrored/backfilled day list against its event: sorted and
    # deduplicated, with full event coverage (or nothing at all) collapsing
    # to nil — the canonical "whole event" storage, matching what
    # Attendances::Upsert does for client-supplied day sets.
    def normalize_days(event, dates)
      if dates.nil? || dates.empty?
        nil
      else
        sorted = dates.uniq.sort
        if event.start_date && sorted == (event.start_date..event.end_date).to_a
          nil
        else
          sorted
        end
      end
    end
  end
end
