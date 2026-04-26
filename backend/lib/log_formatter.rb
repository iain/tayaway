# frozen_string_literal: true

# Logger formatters for APP_LOGGER. Extracted so they can be exercised in
# tests, and so the request-id tagging logic lives in one place rather
# than being duplicated across the production and development branches.
module LogFormatter
  module_function

  # Production: one JSON object per line. Includes request_id when the
  # surrounding code set one via RequestContext, so log aggregation can
  # group all lines from a single request without us having to remember
  # to interpolate the id at every call site.
  def production
    proc do |severity, time, _progname, msg|
      payload = { timestamp: time.utc.iso8601(3), level: severity, message: msg.to_s }
      request_id = RequestContext.request_id
      payload[:request_id] = request_id if request_id
      JSON.generate(payload) + "\n"
    end
  end

  # Development / test: human-readable single line. The DEBUG level drops
  # its label entirely (debug lines tend to be noisy enough already), and
  # the request_id appears as a short bracketed prefix when present.
  def human_readable
    proc do |severity, _time, _progname, msg|
      level_label = severity == "DEBUG" ? "" : "[#{severity}] "
      request_id = RequestContext.request_id
      request_label = request_id ? "[req=#{request_id}] " : ""
      "#{level_label}#{request_label}#{msg}\n"
    end
  end
end
