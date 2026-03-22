# typed: strict
# frozen_string_literal: true

# Tapioca's generated RBI for concurrent-ruby omits ReadWriteLock and
# AtomicBoolean because they are loaded via autoload. We use both in
# app/websocket/listener.rb (AtomicBoolean for the thread-safe running
# flag) and implicitly via concurrent-ruby internals (ReadWriteLock).

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
