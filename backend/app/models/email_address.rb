# typed: true
# frozen_string_literal: true

# Value object for validated email addresses.
class EmailAddress
  extend T::Sig

  REGEX = /\A[^@\s]+@[^@\s]+\z/

  class Invalid < StandardError; end

  sig { returns(String) }
  attr_reader :value

  sig { params(value: String).void }
  def initialize(value)
    raise Invalid, "Email is not valid" unless REGEX.match?(value)

    @value = value
  end

  sig { returns(String) }
  def to_s
    @value
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    case other
    when EmailAddress then other.value == @value
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

  sig { returns(String) }
  def downcase
    @value.downcase
  end

  # Sequel integration - allows EmailAddress to be used directly in queries
  sig { params(ds: T.untyped, sql: String).void }
  def sql_literal_append(ds, sql)
    ds.literal_append(sql, @value)
  end

  class << self
    extend T::Sig
    include Result::Methods

    sig { params(value: T.nilable(String)).returns(Result[EmailAddress, ServiceError]) }
    def parse(value)
      if value.nil? || value.empty?
        Failure(ServiceError.validation("Email is required"))
      else
        Success(new(value))
      end
    rescue Invalid => e
      Failure(ServiceError.validation(e.message))
    end
  end
end
