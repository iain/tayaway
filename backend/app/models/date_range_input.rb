# typed: true
# frozen_string_literal: true

# Value object for validated date range input (start_date <= end_date).
class DateRangeInput
  extend T::Sig

  class Invalid < StandardError; end

  sig { returns(Date) }
  attr_reader :start_date

  sig { returns(Date) }
  attr_reader :end_date

  sig { params(start_date: Date, end_date: Date).void }
  def initialize(start_date, end_date)
    raise Invalid, "End date must be on or after start date" if end_date < start_date

    @start_date = start_date
    @end_date = end_date
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    return false unless other.is_a?(DateRangeInput)

    other.start_date == @start_date && other.end_date == @end_date
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def eql?(other)
    self == other
  end

  sig { returns(Integer) }
  def hash
    [@start_date, @end_date].hash
  end

  class << self
    extend T::Sig
    include Result::Methods

    sig { params(start_date: T.nilable(Date), end_date: T.nilable(Date)).returns(Result[DateRangeInput, ServiceError]) }
    def parse(start_date, end_date)
      if start_date.nil?
        return T.cast(Failure(ServiceError.validation("Start date is required")), Result[DateRangeInput, ServiceError])
      end
      if end_date.nil?
        return T.cast(Failure(ServiceError.validation("End date is required")), Result[DateRangeInput, ServiceError])
      end

      T.cast(Success(new(start_date, end_date)), Result[DateRangeInput, ServiceError])
    rescue Invalid => e
      T.cast(Failure(ServiceError.validation(e.message)), Result[DateRangeInput, ServiceError])
    end

    sig { params(start_str: T.nilable(String), end_str: T.nilable(String)).returns(Result[DateRangeInput, ServiceError]) }
    def parse_strings(start_str, end_str)
      if start_str.nil? || start_str.empty?
        return T.cast(Failure(ServiceError.validation("Start date is required")), Result[DateRangeInput, ServiceError])
      end
      if end_str.nil? || end_str.empty?
        return T.cast(Failure(ServiceError.validation("End date is required")), Result[DateRangeInput, ServiceError])
      end

      begin
        start_date = Date.parse(start_str)
        end_date = Date.parse(end_str)
        parse(start_date, end_date)
      rescue Date::Error
        T.cast(Failure(ServiceError.validation("Invalid date format")), Result[DateRangeInput, ServiceError])
      end
    end
  end
end
