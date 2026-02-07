# typed: true
# frozen_string_literal: true

# Value object for validated UUIDs.
class UUID
  extend T::Sig

  REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  class Invalid < StandardError; end

  sig { returns(String) }
  attr_reader :value

  sig { params(value: String).void }
  def initialize(value)
    raise Invalid, "Invalid UUID format" unless REGEX.match?(value)

    @value = value
  end

  sig { returns(String) }
  def to_s
    @value
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    case other
    when UUID then other.value == @value
    when String then other == @value
    else false
    end
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def eql?(other)
    self == other
  end

  sig { returns(Integer) }
  def hash
    @value.hash
  end

  # Sequel integration - allows UUID to be used directly in queries
  sig { params(dataset: T.untyped, sql: String).void }
  def sql_literal_append(dataset, sql)
    dataset.literal_append(sql, @value)
  end

  class << self
    extend T::Sig
    include Result::Methods

    sig { params(value: T.nilable(String)).returns(Result[UUID, ServiceError]) }
    def parse(value)
      if value.nil? || value.empty?
        return T.cast(Failure(ServiceError.validation("ID is required")), Result[UUID, ServiceError])
      end

      T.cast(Success(new(value)), Result[UUID, ServiceError])
    rescue Invalid => e
      T.cast(Failure(ServiceError.validation(e.message)), Result[UUID, ServiceError])
    end

    sig { returns(UUID) }
    def generate
      new(SecureRandom.uuid)
    end
  end
end
