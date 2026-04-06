# frozen_string_literal: true

# Generates RFC 5545 VCALENDAR strings for all-day events.
# Port of frontend/src/utils/ics.ts.
module IcsGenerator
  class << self
    def generate(uid:, summary:, start_date:, end_date:, created_at:, description: nil, location: nil)
      lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Tayaway//Tayaway//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "BEGIN:VEVENT",
        "UID:#{uid}@tayaway",
        "DTSTAMP:#{format_timestamp(Time.now)}",
        "CREATED:#{format_timestamp(created_at)}",
        "SUMMARY:#{escape_text(summary)}"
      ]

      lines << "DESCRIPTION:#{escape_text(description)}" if description
      lines << "LOCATION:#{escape_text(location)}" if location

      lines << "DTSTART;VALUE=DATE:#{format_date(start_date)}"
      lines << "DTEND;VALUE=DATE:#{format_date(end_date + 1)}"

      lines << "END:VEVENT"
      lines << "END:VCALENDAR"

      lines.map { |line| fold_line(line) }.join("\r\n")
    end

    private

    def escape_text(text)
      # rubocop:disable Style/StringLiterals
      text
        .gsub('\\') { '\\\\' }
        .gsub(";", "\\;")
        .gsub(",", "\\,")
        .gsub("\n", "\\n")
      # rubocop:enable Style/StringLiterals
    end

    def fold_line(line)
      return line if line.bytesize <= 75

      result = line.byteslice(0, 75)
      remaining = line.byteslice(75..)
      while remaining && !remaining.empty?
        result += "\r\n #{remaining.byteslice(0, 74)}"
        remaining = remaining.byteslice(74..)
      end
      result
    end

    def format_date(date)
      date.strftime("%Y%m%d")
    end

    def format_timestamp(time)
      time.utc.strftime("%Y%m%dT%H%M%SZ")
    end
  end
end
