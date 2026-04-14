# frozen_string_literal: true

# Collects and serializes objects for pool-based API responses.
# Objects are deduplicated by type and id, and includes related objects.
#
# @example
#   pool = PoolSerializer.new(workspace_id: workspace_id)
#   pool.add_event(event)
#   { objects: pool.to_a }
class PoolSerializer
  def initialize(workspace_id: nil, membership: nil)
    @objects = {}
    @membership = membership
    @workspace_id = if membership
                      membership.workspace_id.to_s
                    else
                      workspace_id&.to_s
                    end
  end

  # Serializes a workspace membership as a member pool object by fetching the user.
  # This is the canonical entry point used by add_workspace, listener, and sync.
  def add_member_from_membership(membership)
    key = "member:#{membership.id}"
    return if @objects.key?(key)

    user = User.find(membership.user_id)
    return unless user

    hash = build_member_hash(user, membership)
    attach_permissions(hash, membership)
    @objects[key] = hash
  end

  # Public alias for add_member_from_membership
  def add_member(membership)
    add_member_from_membership(membership)
  end

  # Batch-add members with a single User query instead of N+1
  def add_members_batch(memberships)
    new_memberships = memberships.reject { |m| @objects.key?("member:#{m.id}") }
    return if new_memberships.empty?

    user_ids = new_memberships.map { |m| m.user_id.to_s }
    users_by_id = User.for_ids(user_ids).each_with_object({}) { |u, h| h[u.id.to_s] = u }

    new_memberships.each do |m|
      user = users_by_id[m.user_id.to_s]
      next unless user

      hash = build_member_hash(user, m)
      attach_permissions(hash, m)
      @objects["member:#{m.id}"] = hash
    end
  end

  def add_event(event)
    add_batch(ObjectRegistry::BY_KEY["event"], [event])
  end

  def add_events_batch(events)
    add_batch(ObjectRegistry::BY_KEY["event"], events)
  end

  def add_date_poll(date_poll)
    key = "date_poll:#{date_poll.id}"
    return if @objects.key?(key)

    date_range_ids = DateRange.ids_for_date_poll(date_poll.id)
    hash = date_poll.to_api_hash(date_range_ids: date_range_ids)
    attach_permissions(hash, date_poll)
    @objects[key] = hash
  end

  # Batch-add date polls with a single DateRange ID query instead of N+1
  def add_date_polls_batch(polls)
    new_polls = polls.reject { |p| @objects.key?("date_poll:#{p.id}") }
    return if new_polls.empty?

    poll_ids = new_polls.map { |p| p.id.to_s }
    range_ids_by_poll = DateRange.ids_for_date_poll_ids(poll_ids)
    events_by_id = Event.for_ids(new_polls.map { |p| p.event_id.to_s }.uniq).each_with_object({}) { |e, h| h[e.id.to_s] = e }

    new_polls.each do |poll|
      date_range_ids = range_ids_by_poll[poll.id.to_s] || []
      hash = poll.to_api_hash(date_range_ids: date_range_ids)
      attach_permissions(hash, poll, event: events_by_id[poll.event_id.to_s])
      @objects["date_poll:#{poll.id}"] = hash
    end
  end

  def add_date_range(date_range)
    add_batch(ObjectRegistry::BY_KEY["date_range"], [date_range])
  end

  def add_date_ranges_batch(ranges)
    add_batch(ObjectRegistry::BY_KEY["date_range"], ranges)
  end

  def add_vote(vote)
    add_batch(ObjectRegistry::BY_KEY["vote"], [vote])
  end

  def add_rsvp(rsvp)
    add_batch(ObjectRegistry::BY_KEY["rsvp"], [rsvp])
  end

  def add_workspace(workspace)
    key = "workspace:#{workspace.id}"
    return if @objects.key?(key)

    member_ids = WorkspaceMembership.ids_for_workspace(workspace.id)
    hash = workspace.to_api_hash(member_ids: member_ids)
    attach_permissions(hash, workspace)
    @objects[key] = hash
  end

  def add_task_list(task_list)
    key = "task_list:#{task_list.id}"
    return if @objects.key?(key)

    hash = task_list.to_api_hash
    attach_permissions(hash, task_list)
    @objects[key] = hash
    TaskItem.for_task_list(task_list.id).each { |item| add_task_item(item) }
  end

  def add_task_item(task_item)
    key = "task_item:#{task_item.id}"
    return if @objects.key?(key)

    hash = task_item.to_api_hash
    attach_permissions(hash, task_item)
    @objects[key] = hash
  end

  def add_expense(expense, participants: nil)
    key = "expense:#{expense.id}"
    return if @objects.key?(key)

    participants ||= ExpenseParticipant.for_expense(expense.id)
    hash = expense.to_api_hash
    hash[:participantIds] = participants.map { |p| p.id.to_s }
    attach_permissions(hash, expense)
    @objects[key] = hash

    participants.each { |p| add_expense_participant(p) }
  end

  # Batch-add expenses with a single participant query instead of N+1
  def add_expenses_batch(expenses)
    new_expenses = expenses.reject { |e| @objects.key?("expense:#{e.id}") }
    return if new_expenses.empty?

    expense_ids = new_expenses.map { |e| e.id.to_s }
    participants_by_expense = ExpenseParticipant.for_expenses(expense_ids)

    new_expenses.each do |expense|
      add_expense(expense, participants: participants_by_expense[expense.id.to_s] || [])
    end
  end

  def add_expense_participant(participant)
    add_batch(ObjectRegistry::BY_KEY["expense_participant"], [participant])
  end

  def add_settlement(settlement)
    key = "settlement:#{settlement.id}"
    return if @objects.key?(key)

    transfer_ids = SettlementTransfer.ids_for_settlement(settlement.id)
    hash = settlement.to_api_hash(transfer_ids: transfer_ids)
    attach_permissions(hash, settlement)
    @objects[key] = hash
  end

  # Batch-add settlements with a single SettlementTransfer ID query instead of N+1
  def add_settlements_batch(settlements)
    new_settlements = settlements.reject { |s| @objects.key?("settlement:#{s.id}") }
    return if new_settlements.empty?

    settlement_ids = new_settlements.map { |s| s.id.to_s }
    transfer_ids_by_settlement = SettlementTransfer.ids_for_settlement_ids(settlement_ids)
    events_by_id = Event.for_ids(new_settlements.map { |s| s.event_id.to_s }.uniq).each_with_object({}) { |e, h| h[e.id.to_s] = e }

    new_settlements.each do |settlement|
      transfer_ids = transfer_ids_by_settlement[settlement.id.to_s] || []
      hash = settlement.to_api_hash(transfer_ids: transfer_ids)
      attach_permissions(hash, settlement, event: events_by_id[settlement.event_id.to_s])
      @objects["settlement:#{settlement.id}"] = hash
    end
  end

  def add_settlement_transfer(transfer)
    add_batch(ObjectRegistry::BY_KEY["settlement_transfer"], [transfer])
  end

  def add_chore_roster(roster)
    key = "chore_roster:#{roster.id}"
    return if @objects.key?(key)

    chores = Chore.for_roster(roster.id)
    chore_ids = chores.map { |c| c.id.to_s }
    hash = roster.to_api_hash(chore_ids: chore_ids)
    attach_permissions(hash, roster)
    @objects[key] = hash

    # Batch-load all assignments for this roster in one query
    all_assignments = ChoreAssignment.for_roster(roster.id)
    assignments_by_chore = all_assignments.group_by { |a| a.chore_id.to_s }

    chores.each do |chore|
      chore_key = "chore:#{chore.id}"
      next if @objects.key?(chore_key)

      chore_assignments = assignments_by_chore[chore.id.to_s] || []
      assignment_ids = chore_assignments.map { |a| a.id.to_s }
      chore_hash = chore.to_api_hash(assignment_ids: assignment_ids)
      attach_permissions(chore_hash, chore)
      @objects[chore_key] = chore_hash
      chore_assignments.each { |a| add_chore_assignment(a) }
    end
  end

  def add_chore(chore)
    key = "chore:#{chore.id}"
    return if @objects.key?(key)

    assignments = ChoreAssignment.for_chore(chore.id)
    assignment_ids = assignments.map { |a| a.id.to_s }
    hash = chore.to_api_hash(assignment_ids: assignment_ids)
    attach_permissions(hash, chore)
    @objects[key] = hash
    assignments.each { |a| add_chore_assignment(a) }
  end

  def add_chore_assignment(assignment)
    add_batch(ObjectRegistry::BY_KEY["chore_assignment"], [assignment])
  end

  def add_workspace_invite(invite)
    add_batch(ObjectRegistry::BY_KEY["workspace_invite"], [invite])
  end

  def add_all(items, type:)
    entry = ObjectRegistry::BY_KEY[type.to_s]
    unless entry
      APP_LOGGER.warn { "[PoolSerializer] Unknown type in add_all: #{type}" }
      return
    end

    items.each { |item| send(entry.pool_method, item) }
  end

  def to_a
    @objects.values
  end

  private

  def attach_permissions(hash, object, **policy_kwargs)
    return unless @membership

    entry = ObjectRegistry::BY_CLIENT_TYPE[hash[:objectType]]
    return unless entry&.policy

    policy_class = Object.const_get(entry.policy)
    policy = policy_class.new(object, membership: @membership, **policy_kwargs)
    hash[:permissions] = policy.permissions
  end

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

  # New unified path: dispatches to the registry's serializer_class. Returns
  # the number of new objects added (for tests). Legacy add_X methods will
  # delegate to this as each type migrates.
  def add_batch(entry, items)
    return 0 if items.empty?

    serializer = entry.serializer_class
    raise ArgumentError, "No serializer_class for #{entry.key}" unless serializer

    contexts = serializer.policy_context_batch(items)
    hashes = serializer.serialize_batch(items, pool: self)
    added = 0

    items.zip(hashes).each do |obj, hash|
      next unless hash

      key = "#{entry.key}:#{obj.id}"
      next if @objects.key?(key)

      @objects[key] = if @membership
                        PermissionAttacher.call(
                          hash,
                          raw_object: obj,
                          membership: @membership,
                          policy_context: contexts[obj.id.to_s] || {}
                        )
                      else
                        hash
                      end
      added += 1
    end

    added
  end
end
