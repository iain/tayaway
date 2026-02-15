# typed: true
# frozen_string_literal: true

# Collects and serializes objects for pool-based API responses.
# Objects are deduplicated by type and id, and includes related objects.
#
# When workspace_id is provided, user objects are serialized as "member"
# by joining user attributes with workspace membership data.
#
# @example
#   pool = PoolSerializer.new(workspace_id: workspace_id)
#   pool.add_event(event)
#   { objects: pool.to_a }
class PoolSerializer
  extend T::Sig

  extend Result::Methods

  sig { params(event: Event).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
  def self.event_result(event)
    pool = new(workspace_id: event.workspace_id)
    pool.add_event(T.must(Event.find(event.id)))
    T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
  end

  sig { params(workspace_id: T.nilable(T.any(String, UUID))).void }
  def initialize(workspace_id: nil)
    @objects = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
    @workspace_id = T.let(workspace_id&.to_s, T.nilable(String))
    @member_lookup = T.let(nil, T.nilable(T::Hash[String, String]))
  end

  # Lazily builds and caches { user_id_str => membership_id_str } lookup
  sig { params(user_id: T.any(String, UUID)).returns(T.nilable(String)) }
  def member_id_for_user(user_id)
    return nil unless @workspace_id

    @member_lookup ||= WorkspaceMembership.member_id_lookup(@workspace_id)
    @member_lookup[user_id.to_s]
  end

  # Serializes a user as a member pool object using the membership lookup.
  # Skips if no membership found for this user in the workspace.
  sig { params(user: User).void }
  def add_member_from_user(user)
    membership_id = member_id_for_user(user.id)
    return unless membership_id

    key = "member:#{membership_id}"
    return if @objects.key?(key)

    membership = WorkspaceMembership.find(membership_id)
    return unless membership

    @objects[key] = build_member_hash(user, membership)
  end

  # Serializes a workspace membership as a member pool object by fetching the user.
  # This is the canonical entry point used by add_workspace, listener, and sync.
  sig { params(membership: WorkspaceMembership).void }
  def add_member_from_membership(membership)
    key = "member:#{membership.id}"
    return if @objects.key?(key)

    user = User.find(membership.user_id)
    return unless user

    @objects[key] = build_member_hash(user, membership)
  end

  # Public alias for add_member_from_membership
  sig { params(membership: WorkspaceMembership).void }
  def add_member(membership)
    add_member_from_membership(membership)
  end

  sig { params(event: Event, include_workspace: T::Boolean).void }
  def add_event(event, include_workspace: false)
    key = "event:#{event.id}"
    return if @objects.key?(key)

    date_poll = DatePoll.find_by_event(event.id)
    hash = event.to_api_hash(date_poll_id: date_poll&.id&.to_s)

    # Replace userId with memberId
    mid = member_id_for_user(event.user_id)
    if mid
      hash[:memberId] = mid
      hash.delete(:userId)
    end

    @objects[key] = hash

    # Add member for event creator
    user = User.find(event.user_id)
    add_member_from_user(user) if user

    # Add date poll (cascades to date ranges, votes)
    add_date_poll(date_poll) if date_poll

    # Add workspace with members if requested
    if include_workspace
      workspace = Workspace.find(event.workspace_id)
      add_workspace(workspace) if workspace
    end
  end

  sig { params(date_poll: DatePoll).void }
  def add_date_poll(date_poll)
    key = "date_poll:#{date_poll.id}"
    return if @objects.key?(key)

    date_range_ids = DateRange.ids_for_date_poll(date_poll.id)
    @objects[key] = date_poll.to_api_hash(date_range_ids: date_range_ids)

    # Add date ranges
    date_ranges = DateRange.for_date_poll(date_poll.id)
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

    hash = vote.to_api_hash

    # Replace userId with memberId
    mid = member_id_for_user(vote.user_id)
    if mid
      hash[:memberId] = mid
      hash.delete(:userId)
    end

    @objects[key] = hash

    # Add member for voter
    user = User.find(vote.user_id)
    add_member_from_user(user) if user
  end

  sig { params(workspace: Workspace).void }
  def add_workspace(workspace)
    key = "workspace:#{workspace.id}"
    return if @objects.key?(key)

    member_ids = WorkspaceMembership.ids_for_workspace(workspace.id)
    @objects[key] = workspace.to_api_hash(member_ids: member_ids)

    # Add members
    memberships = WorkspaceMembership.for_workspace(workspace.id)
    memberships.each { |m| add_member_from_membership(m) }
  end

  # Adds only the workspace object (no members). Used for the initial
  # sync where we need workspace names for the selector but not full member data.
  sig { params(workspace: Workspace).void }
  def add_workspace_summary(workspace)
    key = "workspace:#{workspace.id}"
    return if @objects.key?(key)

    member_ids = WorkspaceMembership.ids_for_workspace(workspace.id)
    @objects[key] = workspace.to_api_hash(member_ids: member_ids)
  end

  # Adds workspace with all its events (cascading to date_ranges, votes, members)
  sig { params(workspace: Workspace).void }
  def add_workspace_with_events(workspace)
    add_workspace(workspace)
    events = Event.for_workspace(workspace.id)
    events.each { |e| add_event(e) }
  end

  # Flat (non-cascading) methods for partial sync.
  # These serialize the object with required child IDs but don't load/serialize children.

  sig { params(event: Event).void }
  def add_event_flat(event)
    key = "event:#{event.id}"
    return if @objects.key?(key)

    date_poll = DatePoll.find_by_event(event.id)
    hash = event.to_api_hash(date_poll_id: date_poll&.id&.to_s)

    # Replace userId with memberId
    mid = member_id_for_user(event.user_id)
    if mid
      hash[:memberId] = mid
      hash.delete(:userId)
    end

    @objects[key] = hash
  end

  sig { params(date_poll: DatePoll).void }
  def add_date_poll_flat(date_poll)
    key = "date_poll:#{date_poll.id}"
    return if @objects.key?(key)

    date_range_ids = DateRange.ids_for_date_poll(date_poll.id)
    @objects[key] = date_poll.to_api_hash(date_range_ids: date_range_ids)
  end

  sig { params(date_range: DateRange).void }
  def add_date_range_flat(date_range)
    key = "date_range:#{date_range.id}"
    return if @objects.key?(key)

    vote_ids = Vote.ids_for_date_range(date_range.id)
    @objects[key] = date_range.to_api_hash(vote_ids: vote_ids)
  end

  sig { params(workspace: Workspace).void }
  def add_workspace_flat(workspace)
    key = "workspace:#{workspace.id}"
    return if @objects.key?(key)

    member_ids = WorkspaceMembership.ids_for_workspace(workspace.id)
    @objects[key] = workspace.to_api_hash(member_ids: member_ids)
  end

  sig { params(items: T::Enumerable[T.untyped], type: Symbol).void }
  def add_all(items, type:)
    items.each do |item|
      case type
      when :member_from_user then add_member_from_user(item)
      when :member then add_member(item)
      when :event then add_event(item)
      when :date_poll then add_date_poll(item)
      when :date_range then add_date_range(item)
      when :vote then add_vote(item)
      when :workspace then add_workspace(item)
      end
    end
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def to_a
    @objects.values
  end

  private

  sig { params(user: User, membership: WorkspaceMembership).returns(T::Hash[Symbol, T.untyped]) }
  def build_member_hash(user, membership)
    {
      id: membership.id.to_s,
      objectType: "member",
      workspaceId: membership.workspace_id.to_s,
      email: user.email.to_s,
      name: user.name,
      role: membership.role,
      createdAt: membership.created_at.iso8601(3),
      updatedAt: [user.updated_at, membership.updated_at].max.iso8601(3)
    }
  end
end
