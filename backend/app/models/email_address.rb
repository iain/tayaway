# frozen_string_literal: true

# Value object for validated email addresses.
class EmailAddress
  REGEX = /\A[^@\s]+@[^@\s]+\z/

  class Invalid < StandardError; end

  attr_reader :value

  def initialize(value)
    raise Invalid, "Email is not valid" unless REGEX.match?(value)

    @value = value
  end

  def to_s
    @value
  end

  def ==(other)
    case other
    when EmailAddress then other.value == @value
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

  def downcase
    @value.downcase
  end

  # Sequel integration - allows EmailAddress to be used directly in queries
  def sql_literal_append(dataset, sql)
    dataset.literal_append(sql, @value)
  end

  class << self
    include Dry::Monads[:result]

    def parse(value)
      if value.nil? || value.empty?
        return Failure(ServiceError.validation("Email is required"))
      end

      Success(new(value))
    rescue Invalid => e
      Failure(ServiceError.validation(e.message))
    end
  end
end
