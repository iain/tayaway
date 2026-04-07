# frozen_string_literal: true

# Value object for validated UUIDs.
class UUID
  REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  class Invalid < StandardError; end

  attr_reader :value

  def initialize(value)
    raise Invalid, "Invalid UUID format" unless REGEX.match?(value)

    @value = value
  end

  def to_s
    @value
  end

  def ==(other)
    case other
    when UUID then other.value == @value
    when String then other == @value
    else false
    end
  end

  def eql?(other)
    self == other
  end

  def hash
    @value.hash
  end

  # Sequel integration - allows UUID to be used directly in queries
  def sql_literal_append(dataset, sql)
    dataset.literal_append(sql, @value)
  end

  class << self
    include Dry::Monads[:result]

    def parse(value)
      if value.nil? || value.empty?
        return Failure(ServiceError.validation("ID is required"))
      end

      Success(new(value))
    rescue Invalid => e
      Failure(ServiceError.validation(e.message))
    end

    def generate
      new(SecureRandom.uuid)
    end
  end
end
