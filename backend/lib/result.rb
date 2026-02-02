# typed: strict
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
# @example Using helper methods to avoid T.cast
#   module MyService
#     extend T::Sig
#
#     sig { params(value: Integer).returns(Result[Integer, String]) }
#     def self.ok(value)
#       T.cast(Result.Success(value), Result[Integer, String])
#     end
#
#     sig { params(error: String).returns(Result[Integer, String]) }
#     def self.err(error)
#       T.cast(Result.Failure(error), Result[Integer, String])
#     end
#
#     def self.divide(a, b)
#       return err("Division by zero") if b.zero?
#       ok(a / b)
#     end
#   end
#
# @see https://dry-rb.org/gems/dry-monads/1.0/result/ Dry::Monads::Result
class Result
  extend T::Sig
  extend T::Helpers
  extend T::Generic

  SuccessType = type_member
  FailureType = type_member

  abstract!

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
  # @note You'll still need T.cast when using these methods directly.
  #   Consider defining helper methods in your module to avoid repeated T.cast calls.
  module Methods
    extend T::Sig

    # Create a successful Result (Dry::Monads style).
    #
    # @example
    #   Success(42)  # => Success(42)
    sig do
      type_parameters(:S, :F)
        .params(value: T.type_parameter(:S))
        .returns(Result[T.type_parameter(:S), T.type_parameter(:F)])
    end
    def Success(value) # rubocop:disable Naming/MethodName
      Result::Success.new(value)
    end

    # Create a failed Result (Dry::Monads style).
    #
    # @example
    #   Failure("error")  # => Failure("error")
    sig do
      type_parameters(:S, :F)
        .params(error: T.type_parameter(:F))
        .returns(Result[T.type_parameter(:S), T.type_parameter(:F)])
    end
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
  sig { abstract.returns(T::Boolean) }
  def success?; end

  # Check if this is a Failure.
  #
  # @example
  #   Success(42).failure?  # => false
  #   Failure("error").failure?  # => true
  sig { abstract.returns(T::Boolean) }
  def failure?; end

  # Transform the success value with a function (Dry::Monads method).
  #
  # If this is a Success, applies the block to the value and wraps the result
  # in a new Success. If this is a Failure, returns self unchanged.
  #
  # @example
  #   Success(10).fmap { |x| x * 2 }  # => Success(20)
  #   Failure("error").fmap { |x| x * 2 }  # => Failure("error")
  sig do
    abstract
      .type_parameters(:U)
      .params(block: T.proc.params(value: SuccessType).returns(T.type_parameter(:U)))
      .returns(Result[T.type_parameter(:U), FailureType])
  end
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
  sig do
    abstract
      .type_parameters(:U)
      .params(block: T.proc.params(value: SuccessType).returns(Result[T.type_parameter(:U), FailureType]))
      .returns(Result[T.type_parameter(:U), FailureType])
  end
  def bind(&block); end

  # Transform the failure value with a function (Dry::Monads method).
  #
  # If this is a Failure, applies the block to the error and wraps the result
  # in a new Failure. If this is a Success, returns self unchanged.
  #
  # @example
  #   Failure("error").alt_map { |e| "WRAPPED: #{e}" }  # => Failure("WRAPPED: error")
  #   Success(42).alt_map { |e| "WRAPPED: #{e}" }  # => Success(42)
  sig do
    abstract
      .type_parameters(:G)
      .params(block: T.proc.params(error: FailureType).returns(T.type_parameter(:G)))
      .returns(Result[SuccessType, T.type_parameter(:G)])
  end
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
  sig do
    abstract
      .type_parameters(:A)
      .params(
        success_fn: T.proc.params(value: SuccessType).returns(T.type_parameter(:A)),
        failure_fn: T.proc.params(error: FailureType).returns(T.type_parameter(:A))
      )
      .returns(T.type_parameter(:A))
  end
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
  sig do
    abstract
      .type_parameters(:U)
      .params(
        default: T.nilable(T.type_parameter(:U)),
        block: T.nilable(T.proc.params(error: FailureType).returns(T.type_parameter(:U)))
      )
      .returns(T.any(Result[SuccessType, FailureType], T.type_parameter(:U)))
  end
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
  sig do
    abstract
      .params(block: T.proc.params(value: SuccessType).void)
      .returns(T.self_type)
  end
  def tee(&block); end

  # Swap Success and Failure.
  #
  # Converts a Success into a Failure and vice versa, keeping the wrapped value.
  #
  # @example
  #   Success(42).flip  # => Failure(42)
  #   Failure("error").flip  # => Success("error")
  sig { abstract.returns(Result[FailureType, SuccessType]) }
  def flip; end

  # Extract the success value, raising if this is a Failure (Dry::Monads method).
  #
  # @example
  #   Success(42).value!  # => 42
  #   Failure("error").value!  # raises RuntimeError
  #
  # @see #value_or
  sig { abstract.returns(SuccessType) }
  def value!; end

  # Extract the failure value, raising if this is a Success (Dry::Monads method).
  #
  # @example
  #   Failure("error").failure  # => "error"
  #   Success(42).failure  # raises RuntimeError
  sig { abstract.returns(FailureType) }
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
  sig { abstract.params(default: SuccessType).returns(SuccessType) }
  def value_or(default); end

  # String representation of the Result.
  #
  # @example
  #   Success(42).to_s  # => "Success(42)"
  #   Failure("error").to_s  # => "Failure(\"error\")"
  sig { abstract.returns(String) }
  def to_s; end

  # Detailed string representation (same as {#to_s}).
  #
  # @example
  #   Success(42).inspect  # => "Success(42)"
  sig { abstract.returns(String) }
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
    extend T::Sig
    extend T::Generic

    SuccessType = type_member
    FailureType = type_member

    # Create a new Success instance.
    #
    # @api private
    sig { params(value: SuccessType).void }
    def initialize(value) # rubocop:disable Lint/MissingSuper
      @value = value
    end

    sig { override.returns(T::Boolean) }
    def success?
      true
    end

    sig { override.returns(T::Boolean) }
    def failure?
      false
    end

    sig do
      override
        .type_parameters(:U)
        .params(block: T.proc.params(value: SuccessType).returns(T.type_parameter(:U)))
        .returns(Result[T.type_parameter(:U), FailureType])
    end
    def fmap(&block)
      Success.new(yield(@value))
    end

    sig do
      override
        .type_parameters(:U)
        .params(block: T.proc.params(value: SuccessType).returns(Result[T.type_parameter(:U), FailureType]))
        .returns(Result[T.type_parameter(:U), FailureType])
    end
    def bind(&block)
      yield(@value)
    end

    sig do
      override
        .type_parameters(:G)
        .params(block: T.proc.params(error: FailureType).returns(T.type_parameter(:G)))
        .returns(Result[SuccessType, T.type_parameter(:G)])
    end
    def alt_map(&block)
      T.cast(self, Result[SuccessType, T.type_parameter(:G)])
    end

    sig do
      override
        .type_parameters(:A)
        .params(
          success_fn: T.proc.params(value: SuccessType).returns(T.type_parameter(:A)),
          failure_fn: T.proc.params(error: FailureType).returns(T.type_parameter(:A))
        )
        .returns(T.type_parameter(:A))
    end
    def either(success_fn, failure_fn)
      success_fn.call(@value)
    end

    sig do
      override
        .type_parameters(:U)
        .params(
          default: T.nilable(T.type_parameter(:U)),
          block: T.nilable(T.proc.params(error: FailureType).returns(T.type_parameter(:U)))
        )
        .returns(T.any(Result[SuccessType, FailureType], T.type_parameter(:U)))
    end
    def or(default = nil, &block)
      self
    end

    sig do
      override
        .params(block: T.proc.params(value: SuccessType).void)
        .returns(T.self_type)
    end
    def tee(&block)
      yield(@value)
      self
    end

    sig { override.returns(Result[FailureType, SuccessType]) }
    def flip
      Failure.new(@value)
    end

    sig { override.returns(SuccessType) }
    def value!
      @value
    end

    sig { override.returns(FailureType) }
    def failure
      raise "Called failure on a Success"
    end

    sig { override.params(default: SuccessType).returns(SuccessType) }
    def value_or(default)
      @value
    end

    sig { override.returns(String) }
    def to_s
      "Success(#{T.unsafe(@value).inspect})"
    end

    sig { override.returns(String) }
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
    extend T::Sig
    extend T::Generic

    SuccessType = type_member
    FailureType = type_member

    # Create a new Failure instance.
    #
    # @api private
    sig { params(error: FailureType).void }
    def initialize(error) # rubocop:disable Lint/MissingSuper
      @error = error
    end

    sig { override.returns(T::Boolean) }
    def success?
      false
    end

    sig { override.returns(T::Boolean) }
    def failure?
      true
    end

    sig do
      override
        .type_parameters(:U)
        .params(block: T.proc.params(value: SuccessType).returns(T.type_parameter(:U)))
        .returns(Result[T.type_parameter(:U), FailureType])
    end
    def fmap(&block)
      T.cast(self, Result[T.type_parameter(:U), FailureType])
    end

    sig do
      override
        .type_parameters(:U)
        .params(block: T.proc.params(value: SuccessType).returns(Result[T.type_parameter(:U), FailureType]))
        .returns(Result[T.type_parameter(:U), FailureType])
    end
    def bind(&block)
      T.cast(self, Result[T.type_parameter(:U), FailureType])
    end

    sig do
      override
        .type_parameters(:G)
        .params(block: T.proc.params(error: FailureType).returns(T.type_parameter(:G)))
        .returns(Result[SuccessType, T.type_parameter(:G)])
    end
    def alt_map(&block)
      Failure.new(yield(@error))
    end

    sig do
      override
        .type_parameters(:A)
        .params(
          success_fn: T.proc.params(value: SuccessType).returns(T.type_parameter(:A)),
          failure_fn: T.proc.params(error: FailureType).returns(T.type_parameter(:A))
        )
        .returns(T.type_parameter(:A))
    end
    def either(success_fn, failure_fn)
      failure_fn.call(@error)
    end

    sig do
      override
        .type_parameters(:U)
        .params(
          default: T.nilable(T.type_parameter(:U)),
          block: T.nilable(T.proc.params(error: FailureType).returns(T.type_parameter(:U)))
        )
        .returns(T.any(Result[SuccessType, FailureType], T.type_parameter(:U)))
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

    sig do
      override
        .params(block: T.proc.params(value: SuccessType).void)
        .returns(T.self_type)
    end
    def tee(&block)
      self
    end

    sig { override.returns(Result[FailureType, SuccessType]) }
    def flip
      Success.new(@error)
    end

    sig { override.returns(SuccessType) }
    def value!
      raise "Called value! on a Failure: #{T.unsafe(@error).inspect}"
    end

    sig { override.returns(FailureType) }
    def failure
      @error
    end

    sig { override.params(default: SuccessType).returns(SuccessType) }
    def value_or(default)
      default
    end

    sig { override.returns(String) }
    def to_s
      "Failure(#{T.unsafe(@error).inspect})"
    end

    sig { override.returns(String) }
    def inspect
      to_s
    end
  end
end
