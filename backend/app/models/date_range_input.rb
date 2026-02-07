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
    other.is_a?(DateRangeInput) && other.start_date == @start_date && other.end_date == @end_date
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
        Failure(ServiceError.validation("Start date is required"))
      elsif end_date.nil?
        Failure(ServiceError.validation("End date is required"))
      else
        Success(new(start_date, end_date))
      end
    rescue Invalid => e
      Failure(ServiceError.validation(e.message))
    end

    sig { params(start_str: T.nilable(String), end_str: T.nilable(String)).returns(Result[DateRangeInput, ServiceError]) }
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
