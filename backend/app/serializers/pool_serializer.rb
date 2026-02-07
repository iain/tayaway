# typed: true
# frozen_string_literal: true

# Collects and serializes objects for pool-based API responses.
# Objects are deduplicated by type and id, and includes related objects.
#
# @example
#   pool = PoolSerializer.new
#   pool.add(event)
#   { event: { id: event.id }, objects: pool.to_a }
class PoolSerializer
  extend T::Sig

  sig { void }
  def initialize
    @objects = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
  end

  sig { params(record: T.untyped).void }
  def add(record)
    return if record.nil?

    key = "#{record.class.name}:#{record.id}"
    return if @objects.key?(key)

    @objects[key] = record.to_pool_hash
    collect_related(record)
  end

  sig { params(records: T::Enumerable[T.untyped]).void }
  def add_all(records)
    records.each { |r| add(r) }
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def to_a
    @objects.values
  end

  private

  sig { params(record: T.untyped).void }
  def collect_related(record)
    case record
    when Event
      add(record.user) if record.user
      record.date_ranges.each { |dr| add(dr) }
    when DateRange
      record.votes.each { |v| add(v) }
    when Vote
      add(record.user) if record.user
    end
  end
end
