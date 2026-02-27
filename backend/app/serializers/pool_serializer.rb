# typed: true
# frozen_string_literal: true

# Collects and serializes objects for pool-based API responses.
# Objects are deduplicated by type and id, and includes related objects.
#
# @example
#   pool = PoolSerializer.new(workspace_id: workspace_id)
#   pool.add_event(event)
#   { objects: pool.to_a }
class PoolSerializer
  extend T::Sig

  sig { params(workspace_id: T.nilable(T.any(String, UUID))).void }
  def initialize(workspace_id: nil)
    @objects = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
    @workspace_id = T.let(workspace_id&.to_s, T.nilable(String))
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

  sig { params(event: Event).void }
  def add_event(event)
    key = "event:#{event.id}"
    return if @objects.key?(key)

    date_poll = DatePoll.find_by_event(event.id)
    hash = event.to_api_hash(date_poll_id: date_poll&.id&.to_s)
    hash[:rsvpIds] = Rsvp.ids_for_event(event.id)

    @objects[key] = hash
  end

  sig { params(date_poll: DatePoll).void }
  def add_date_poll(date_poll)
    key = "date_poll:#{date_poll.id}"
    return if @objects.key?(key)

    date_range_ids = DateRange.ids_for_date_poll(date_poll.id)
    @objects[key] = date_poll.to_api_hash(date_range_ids: date_range_ids)
  end

  sig { params(date_range: DateRange).void }
  def add_date_range(date_range)
    key = "date_range:#{date_range.id}"
    return if @objects.key?(key)

    vote_ids = Vote.ids_for_date_range(date_range.id)
    @objects[key] = date_range.to_api_hash(vote_ids: vote_ids)
  end

  sig { params(vote: Vote).void }
  def add_vote(vote)
    key = "vote:#{vote.id}"
    return if @objects.key?(key)

    @objects[key] = vote.to_api_hash
  end

  sig { params(rsvp: Rsvp).void }
  def add_rsvp(rsvp)
    key = "rsvp:#{rsvp.id}"
    return if @objects.key?(key)

    @objects[key] = rsvp.to_api_hash
  end

  sig { params(workspace: Workspace).void }
  def add_workspace(workspace)
    key = "workspace:#{workspace.id}"
    return if @objects.key?(key)

    member_ids = WorkspaceMembership.ids_for_workspace(workspace.id)
    @objects[key] = workspace.to_api_hash(member_ids: member_ids)
  end

  sig { params(task_list: TaskList).void }
  def add_task_list(task_list)
    key = "task_list:#{task_list.id}"
    return if @objects.key?(key)

    @objects[key] = task_list.to_api_hash
    TaskItem.for_task_list(task_list.id).each { |item| add_task_item(item) }
  end

  sig { params(task_item: TaskItem).void }
  def add_task_item(task_item)
    key = "task_item:#{task_item.id}"
    return if @objects.key?(key)

    @objects[key] = task_item.to_api_hash
  end

  sig { params(expense: Expense).void }
  def add_expense(expense)
    key = "expense:#{expense.id}"
    return if @objects.key?(key)

    @objects[key] = expense.to_api_hash
  end

  sig { params(settlement: Settlement).void }
  def add_settlement(settlement)
    key = "settlement:#{settlement.id}"
    return if @objects.key?(key)

    transfer_ids = SettlementTransfer.ids_for_settlement(settlement.id)
    @objects[key] = settlement.to_api_hash(transfer_ids: transfer_ids)
  end

  sig { params(transfer: SettlementTransfer).void }
  def add_settlement_transfer(transfer)
    key = "settlement_transfer:#{transfer.id}"
    return if @objects.key?(key)

    @objects[key] = transfer.to_api_hash
  end

  sig { params(items: T::Enumerable[T.untyped], type: Symbol).void }
  def add_all(items, type:)
    entry = ObjectRegistry::BY_KEY[type.to_s]
    if entry
      items.each { |item| send(entry.pool_method, item) }
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
      userId: user.id.to_s,
      email: user.email.to_s,
      name: user.name,
      phoneNumber: user.phone_number,
      birthday: user.birthday&.iso8601,
      locationName: user.location_name,
      latitude: user.location_coordinates&.[](1),
      longitude: user.location_coordinates&.[](0),
      hasIban: !user.iban.nil?,
      role: membership.role,
      createdAt: membership.created_at.iso8601(3),
      updatedAt: [user.updated_at, membership.updated_at].max.iso8601(3)
    }
  end
end
