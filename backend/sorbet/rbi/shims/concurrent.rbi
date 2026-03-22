# typed: strict
# frozen_string_literal: true

class Concurrent::ReadWriteLock
end

class Concurrent::AtomicBoolean
  sig { params(initial: T::Boolean).void }
  def initialize(initial = false); end

  sig { returns(T::Boolean) }
  def true?; end

  sig { returns(T::Boolean) }
  def false?; end

  sig { params(value: T::Boolean).void }
  def value=(value); end

  sig { returns(T::Boolean) }
  def make_true; end

  sig { returns(T::Boolean) }
  def make_false; end
end
