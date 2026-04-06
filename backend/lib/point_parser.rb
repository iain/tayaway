# frozen_string_literal: true

# Parses PostgreSQL POINT strings into [longitude, latitude] float arrays.
module PointParser
  # Parses a PostgreSQL POINT string of the form "(x,y)" into [x.to_f, y.to_f].
  # Returns nil for nil, empty strings, or strings that don't match the expected format.
  def self.parse(point)
    return unless point.is_a?(String) && point.match?(/\A\(.+,.+\)\z/)

    parts = point.delete("()").split(",")
    [parts[0].to_f, parts[1].to_f]
  end
end
