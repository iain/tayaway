# frozen_string_literal: true

# A Result monad representing either a successful value or a failure value.
#
# The Result monad is a container type that represents the result of a computation
# that might fail. It has two variants:
# - {Success} - represents a successful computation with a value
# - {Failure} - represents a failed computation with an error
#
# This implementation is compatible with the Dry::Monads::Result API.
#
# @example Basic usage
#   result = Success(42)
#   result.success?  # => true
#   result.value!    # => 42
#
#   error = Failure("oops")
#   error.failure?   # => true
#   error.failure    # => "oops"
#
# @example Chaining operations
#   Success(10)
#     .fmap { |x| x * 2 }
#     .bind { |x| Success(x + 5) }
#     .value_or(0)  # => 25
#
# @example Using helper methods
#   module MyService
#     include Result::Methods
#
#     def self.divide(a, b)
#       return Failure("Division by zero") if b.zero?
#       Success(a / b)
#     end
#   end
#
# @see https://dry-rb.org/gems/dry-monads/1.0/result/ Dry::Monads::Result
class Result
  # Factory methods module that can be extended into other classes/modules.
  #
  # Provides {#Success} and {#Failure} methods for creating Result instances.
  # Extend this module to get access to these factory methods.
  #
  # @example
  #   module MyService
  #     extend Result::Methods
  #
  #     def self.process(value)
  #       Success(value)  # or Failure(error)
  #     end
  #   end
  #
  module Methods
    # Create a successful Result (Dry::Monads style).
    #
    # @example
    #   Success(42)  # => Success(42)
    def Success(value) # rubocop:disable Naming/MethodName
      Result::Success.new(value)
    end

    # Create a failed Result (Dry::Monads style).
    #
    # @example
    #   Failure("error")  # => Failure("error")
    def Failure(error) # rubocop:disable Naming/MethodName
      Result::Failure.new(error)
    end
  end

  extend Methods

  # Check if this is a Success.
  #
  # @example
  #   Success(42).success?  # => true
  #   Failure("error").success?  # => false
  def success?; end

  # Check if this is a Failure.
  #
  # @example
  #   Success(42).failure?  # => false
  #   Failure("error").failure?  # => true
  def failure?; end

  # Transform the success value with a function (Dry::Monads method).
  #
  # If this is a Success, applies the block to the value and wraps the result
  # in a new Success. If this is a Failure, returns self unchanged.
  #
  # @example
  #   Success(10).fmap { |x| x * 2 }  # => Success(20)
  #   Failure("error").fmap { |x| x * 2 }  # => Failure("error")
  def fmap(&block); end

  # Chain Result-returning operations (Dry::Monads method).
  #
  # If this is a Success, applies the block to the value and returns the
  # resulting Result. If this is a Failure, returns self unchanged.
  # This is useful for chaining operations that might fail.
  #
  # @example
  #   Success(10).bind { |x| Success(x + 5) }  # => Success(15)
  #   Success(10).bind { |x| Failure("error") }  # => Failure("error")
  #   Failure("error").bind { |x| Success(x + 5) }  # => Failure("error")
  def bind(&block); end

  # Transform the failure value with a function (Dry::Monads method).
  #
  # If this is a Failure, applies the block to the error and wraps the result
  # in a new Failure. If this is a Success, returns self unchanged.
  #
  # @example
  #   Failure("error").alt_map { |e| "WRAPPED: #{e}" }  # => Failure("WRAPPED: error")
  #   Success(42).alt_map { |e| "WRAPPED: #{e}" }  # => Success(42)
  def alt_map(&block); end

  # Pattern match on both Success and Failure cases.
  #
  # Applies the appropriate function based on whether this is a Success or Failure.
  # This is useful when you need to handle both cases and return the same type.
  #
  # @example
  #   result = Success(42)
  #   result.either(
  #     ->(x) { "Success: #{x}" },
  #     ->(e) { "Failure: #{e}" }
  #   )  # => "Success: 42"
  #
  # @example With a Failure
  #   result = Failure("error")
  #   result.either(
  #     ->(x) { "Success: #{x}" },
  #     ->(e) { "Failure: #{e}" }
  #   )  # => "Failure: error"
  def either(success_fn, failure_fn); end

  # Provide alternative value for Failure case.
  #
  # If this is a Success, returns self. If this is a Failure, returns the
  # provided default value or calls the block with the error.
  #
  # @example With default value
  #   Success(42).or(0)  # => Success(42)
  #   Failure("error").or(0)  # => 0
  #
  # @example With block
  #   Failure("error").or { |e| e.length }  # => 5
  def or(default = nil, &block); end

  # Execute a side effect on Success without changing the value.
  #
  # If this is a Success, calls the block with the value and returns self.
  # If this is a Failure, returns self without calling the block.
  # Useful for logging or other side effects.
  #
  # @example
  #   Success(42).tee { |x| puts "Value: #{x}" }  # prints "Value: 42", returns Success(42)
  #   Failure("error").tee { |x| puts x }  # returns Failure("error") without printing
  def tee(&block); end

  # Swap Success and Failure.
  #
  # Converts a Success into a Failure and vice versa, keeping the wrapped value.
  #
  # @example
  #   Success(42).flip  # => Failure(42)
  #   Failure("error").flip  # => Success("error")
  def flip; end

  # Extract the success value, raising if this is a Failure (Dry::Monads method).
  #
  # @example
  #   Success(42).value!  # => 42
  #   Failure("error").value!  # raises RuntimeError
  #
  # @see #value_or
  def value!; end

  # Extract the failure value, raising if this is a Success (Dry::Monads method).
  #
  # @example
  #   Failure("error").failure  # => "error"
  #   Success(42).failure  # raises RuntimeError
  def failure; end

  # Safely extract the value with a default fallback.
  #
  # Returns the success value if this is a Success, otherwise returns
  # the provided default.
  #
  # @example
  #   Success(42).value_or(0)  # => 42
  #   Failure("error").value_or(0)  # => 0
  #
  # @see #value!
  def value_or(default); end

  # String representation of the Result.
  #
  # @example
  #   Success(42).to_s  # => "Success(42)"
  #   Failure("error").to_s  # => "Failure(\"error\")"
  def to_s; end

  # Detailed string representation (same as {#to_s}).
  #
  # @example
  #   Success(42).inspect  # => "Success(42)"
  def inspect; end

  # Success variant of Result.
  #
  # Represents a successful computation with a value.
  # Do not instantiate directly; use {Success} instead.
  #
  # @example
  #   success = Success(42)
  #   success.success?  # => true
  #   success.value!    # => 42
  class Success < Result
    # Create a new Success instance.
    #
    # @api private
    def initialize(value) # rubocop:disable Lint/MissingSuper
      @value = value
    end

    def success?
      true
    end

    def failure?
      false
    end

    def fmap(&block)
      Success.new(yield(@value))
    end

    def bind(&block)
      yield(@value)
    end

    def alt_map(&block)
      self
    end

    def either(success_fn, failure_fn)
      success_fn.call(@value)
    end

    def or(default = nil, &block)
      self
    end

    def tee(&block)
      yield(@value)
      self
    end

    def flip
      Failure.new(@value)
    end

    def value!
      @value
    end

    def failure
      raise "Called failure on a Success"
    end

    def value_or(default)
      @value
    end

    def to_s
      "Success(#{@value.inspect})"
    end

    def inspect
      to_s
    end
  end

  # Failure variant of Result.
  #
  # Represents a failed computation with an error value.
  # Do not instantiate directly; use {Failure} instead.
  #
  # @example
  #   failure = Failure("error message")
  #   failure.failure?  # => true
  #   failure.failure   # => "error message"
  class Failure < Result
    # Create a new Failure instance.
    #
    # @api private
    def initialize(error) # rubocop:disable Lint/MissingSuper
      @error = error
    end

    def success?
      false
    end

    def failure?
      true
    end

    def fmap(&block)
      self
    end

    def bind(&block)
      self
    end

    def alt_map(&block)
      Failure.new(yield(@error))
    end

    def either(success_fn, failure_fn)
      failure_fn.call(@error)
    end

    def or(default = nil, &block)
      if block
        yield(@error)
      elsif default
        default
      else
        self
      end
    end

    def tee(&block)
      self
    end

    def flip
      Success.new(@error)
    end

    def value!
      raise "Called value! on a Failure: #{@error.inspect}"
    end

    def failure
      @error
    end

    def value_or(default)
      default
    end

    def to_s
      "Failure(#{@error.inspect})"
    end

    def inspect
      to_s
    end
  end
end
