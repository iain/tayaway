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

  # Batch-add members with a single User query instead of N+1
  sig { params(memberships: T::Array[WorkspaceMembership]).void }
  def add_members_batch(memberships)
    new_memberships = memberships.reject { |m| @objects.key?("member:#{m.id}") }
    return if new_memberships.empty?

    user_ids = new_memberships.map { |m| m.user_id.to_s }
    users_by_id = User.for_ids(user_ids).each_with_object({}) { |u, h| h[u.id.to_s] = u }

    new_memberships.each do |m|
      user = users_by_id[m.user_id.to_s]
      next unless user

      @objects["member:#{m.id}"] = build_member_hash(user, m)
    end
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

  sig { params(roster: ChoreRoster).void }
  def add_chore_roster(roster)
    key = "chore_roster:#{roster.id}"
    return if @objects.key?(key)

    chores = Chore.for_roster(roster.id)
    chore_ids = chores.map { |c| c.id.to_s }
    @objects[key] = roster.to_api_hash(chore_ids: chore_ids)

    # Batch-load all assignments for this roster in one query
    all_assignments = ChoreAssignment.for_roster(roster.id)
    assignments_by_chore = all_assignments.group_by { |a| a.chore_id.to_s }

    chores.each do |chore|
      chore_key = "chore:#{chore.id}"
      next if @objects.key?(chore_key)

      chore_assignments = assignments_by_chore[chore.id.to_s] || []
      assignment_ids = chore_assignments.map { |a| a.id.to_s }
      @objects[chore_key] = chore.to_api_hash(assignment_ids: assignment_ids)
      chore_assignments.each { |a| add_chore_assignment(a) }
    end
  end

  sig { params(chore: Chore).void }
  def add_chore(chore)
    key = "chore:#{chore.id}"
    return if @objects.key?(key)

    assignments = ChoreAssignment.for_chore(chore.id)
    assignment_ids = assignments.map { |a| a.id.to_s }
    @objects[key] = chore.to_api_hash(assignment_ids: assignment_ids)
    assignments.each { |a| add_chore_assignment(a) }
  end

  sig { params(assignment: ChoreAssignment).void }
  def add_chore_assignment(assignment)
    key = "chore_assignment:#{assignment.id}"
    return if @objects.key?(key)

    @objects[key] = assignment.to_api_hash
  end

  sig { params(invite: WorkspaceInvite).void }
  def add_workspace_invite(invite)
    key = "workspace_invite:#{invite.id}"
    return if @objects.key?(key)

    @objects[key] = invite.to_api_hash
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
