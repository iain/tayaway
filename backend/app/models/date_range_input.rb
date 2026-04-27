# frozen_string_literal: true

# Value object for validated date range input (start_date <= end_date).
class DateRangeInput
  class Invalid < StandardError; end

  attr_reader :start_date

  attr_reader :end_date

  def initialize(start_date, end_date)
    raise Invalid, "End date must be on or after start date" if end_date < start_date

    @start_date = start_date
    @end_date = end_date
  end

  def ==(other)
    return false unless other.is_a?(DateRangeInput)

    other.start_date == @start_date && other.end_date == @end_date
  end

  def eql?(other)
    self == other
  end

  def hash
    [@start_date, @end_date].hash
  end

  class << self
    def parse(start_date, end_date)
      if start_date.nil?
        return Failure(ServiceError.validation("Start date is required"))
      end
      if end_date.nil?
        return Failure(ServiceError.validation("End date is required"))
      end

      Success(new(start_date, end_date))
    rescue Invalid => e
      Failure(ServiceError.validation(e.message))
    end

    def parse_strings(start_str, end_str)
      if start_str.nil? || start_str.empty?
        return Failure(ServiceError.validation("Start date is required"))
      end
      if end_str.nil? || end_str.empty?
        return Failure(ServiceError.validation("End date is required"))
      end

      begin
        start_date = Date.parse(start_str)
        end_date = Date.parse(end_str)
        parse(start_date, end_date)
      rescue Date::Error
        Failure(ServiceError.validation("Invalid date format"))
      end
    end
  end
end
