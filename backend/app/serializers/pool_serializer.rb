# typed: true
# frozen_string_literal: true

# Collects and serializes objects for pool-based API responses.
# Objects are deduplicated by type and id, and includes related objects.
#
# @example
#   pool = PoolSerializer.new
#   pool.add_event(event)
#   { objects: pool.to_a }
class PoolSerializer
  extend T::Sig

  sig { void }
  def initialize
    @objects = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
  end

  sig { params(user: User).void }
  def add_user(user)
    key = "user:#{user.id}"
    return if @objects.key?(key)

    @objects[key] = user.to_api_hash
  end

  sig { params(event: Event).void }
  def add_event(event)
    key = "event:#{event.id}"
    return if @objects.key?(key)

    date_range_ids = DateRange.ids_for_event(event.id)
    @objects[key] = event.to_api_hash(date_range_ids: date_range_ids)

    # Add user
    user = User.find(event.user_id)
    add_user(user) if user

    # Add date ranges
    date_ranges = DateRange.for_event(event.id)
    date_ranges.each { |dr| add_date_range(dr) }
  end

  sig { params(date_range: DateRange).void }
  def add_date_range(date_range)
    key = "date_range:#{date_range.id}"
    return if @objects.key?(key)

    vote_ids = Vote.ids_for_date_range(date_range.id)
    @objects[key] = date_range.to_api_hash(vote_ids: vote_ids)

    # Add votes
    votes = Vote.for_date_range(date_range.id)
    votes.each { |v| add_vote(v) }
  end

  sig { params(vote: Vote).void }
  def add_vote(vote)
    key = "vote:#{vote.id}"
    return if @objects.key?(key)

    @objects[key] = vote.to_api_hash

    # Add user
    user = User.find(vote.user_id)
    add_user(user) if user
  end

  sig { params(workspace: Workspace).void }
  def add_workspace(workspace)
    key = "workspace:#{workspace.id}"
    return if @objects.key?(key)

    membership_ids = WorkspaceMembership.ids_for_workspace(workspace.id)
    @objects[key] = workspace.to_api_hash(membership_ids: membership_ids)

    # Add memberships
    memberships = WorkspaceMembership.for_workspace(workspace.id)
    memberships.each { |m| add_workspace_membership(m) }
  end

  sig { params(membership: WorkspaceMembership).void }
  def add_workspace_membership(membership)
    key = "workspace_membership:#{membership.id}"
    return if @objects.key?(key)

    @objects[key] = membership.to_api_hash

    # Add user
    user = User.find(membership.user_id)
    add_user(user) if user
  end

  sig { params(items: T::Enumerable[T.untyped], type: Symbol).void }
  def add_all(items, type:)
    items.each do |item|
      case type
      when :user then add_user(item)
      when :event then add_event(item)
      when :date_range then add_date_range(item)
      when :vote then add_vote(item)
      when :workspace then add_workspace(item)
      when :workspace_membership then add_workspace_membership(item)
      end
    end
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def to_a
    @objects.values
  end
end
