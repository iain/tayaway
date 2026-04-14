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

  # New unified entry point. Takes a registry key (symbol or string) and
  # an array of items. Dispatches to the registered serializer_class.
  def add(key, items)
    entry = ObjectRegistry::BY_KEY[key.to_s]
    raise ArgumentError, "Unknown object key: #{key.inspect}" unless entry

    add_batch(entry, Array(items))
  end

  # Serializes a workspace membership as a member pool object.
  def add_member_from_membership(membership)
    add_batch(ObjectRegistry::BY_KEY["member"], [membership])
  end

  # Public alias.
  def add_member(membership)
    add_batch(ObjectRegistry::BY_KEY["member"], [membership])
  end

  def add_members_batch(memberships)
    add_batch(ObjectRegistry::BY_KEY["member"], memberships)
  end

  def add_event(event)
    add_batch(ObjectRegistry::BY_KEY["event"], [event])
  end

  def add_events_batch(events)
    add_batch(ObjectRegistry::BY_KEY["event"], events)
  end

  def add_date_poll(date_poll)
    add_batch(ObjectRegistry::BY_KEY["date_poll"], [date_poll])
  end

  def add_date_polls_batch(polls)
    add_batch(ObjectRegistry::BY_KEY["date_poll"], polls)
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
    add_batch(ObjectRegistry::BY_KEY["workspace"], [workspace])
  end

  def add_task_list(task_list)
    add_batch(ObjectRegistry::BY_KEY["task_list"], [task_list])
  end

  def add_task_item(task_item)
    add_batch(ObjectRegistry::BY_KEY["task_item"], [task_item])
  end

  def add_expense(expense, participants: nil)
    add_batch(ObjectRegistry::BY_KEY["expense"], [expense])
  end

  def add_expenses_batch(expenses)
    add_batch(ObjectRegistry::BY_KEY["expense"], expenses)
  end

  def add_expense_participant(participant)
    add_batch(ObjectRegistry::BY_KEY["expense_participant"], [participant])
  end

  def add_settlement(settlement)
    add_batch(ObjectRegistry::BY_KEY["settlement"], [settlement])
  end

  def add_settlements_batch(settlements)
    add_batch(ObjectRegistry::BY_KEY["settlement"], settlements)
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
