# frozen_string_literal: true

# Tests for Sync Engine v2 guarantees put the guarantee's ID in their
# description, e.g. "[SYNC-G-302] returns rows committed late". A guarantee
# that doesn't hold yet gets `known_gap: true`: the example still runs, is
# reported as pending while it fails, and fails the suite once it passes, so
# the marker has to be removed. scripts/sync-coverage reads the "Known gap"
# message from the JSON results. See doc/sync/roadmap.md.
RSpec.configure do |config|
  config.define_derived_metadata(known_gap: true) do |metadata|
    metadata[:pending] = "Known gap"
  end
end
