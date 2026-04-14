# frozen_string_literal: true

# Central registry of all pool object types. Single source of truth used by
# Websocket::Listener, Sync::WorkspaceSync, and PoolSerializer.
module ObjectRegistry
  class Entry
    attr_reader :key, :model, :client_type, :pool_method, :tracks_user, :policy, :serializer_class

    def initialize(
      key:,
      model:,
      client_type:,
      pool_method:,
      tracks_user:,
      policy: nil,
      serializer_class: nil
    )
      @key = key
      @model = model
      @client_type = client_type
      @pool_method = pool_method
      @tracks_user = tracks_user
      @policy = policy
      @serializer_class = serializer_class
    end
  end

  TYPES = [
    Entry.new(key: "event", model: "Event", client_type: "event", pool_method: :add_event, tracks_user: true, policy: "EventPolicy", serializer_class: EventSerializer),
    Entry.new(key: "workspace",   model: "Workspace",            client_type: "workspace",  pool_method: :add_workspace,   tracks_user: false, policy: "WorkspacePolicy"),
    Entry.new(key: "member",      model: "WorkspaceMembership",  client_type: "member",     pool_method: :add_member,      tracks_user: false, policy: "MemberPolicy"),
    Entry.new(key: "date_poll",   model: "DatePoll",             client_type: "datePoll",   pool_method: :add_date_poll,   tracks_user: false, policy: "DatePollPolicy"),
    Entry.new(key: "date_range",  model: "DateRange",            client_type: "dateRange",  pool_method: :add_date_range,  tracks_user: false, policy: "DateRangePolicy", serializer_class: DateRangeSerializer),
    Entry.new(key: "vote",        model: "Vote",                 client_type: "vote",       pool_method: :add_vote,        tracks_user: true,  policy: "VotePolicy", serializer_class: VoteSerializer),
    Entry.new(key: "rsvp",        model: "Rsvp",                 client_type: "rsvp",       pool_method: :add_rsvp,        tracks_user: true,  policy: "RsvpPolicy", serializer_class: RsvpSerializer),
    Entry.new(key: "task_list",   model: "TaskList",             client_type: "taskList",   pool_method: :add_task_list,   tracks_user: true,  policy: "TaskListPolicy"),
    Entry.new(key: "task_item",   model: "TaskItem",             client_type: "taskItem",   pool_method: :add_task_item,   tracks_user: true,  policy: "TaskItemPolicy"),
    Entry.new(key: "expense",     model: "Expense",              client_type: "expense",    pool_method: :add_expense,     tracks_user: true,  policy: "ExpensePolicy"),
    Entry.new(key: "settlement",  model: "Settlement",           client_type: "settlement", pool_method: :add_settlement,  tracks_user: true,  policy: "SettlementPolicy"),
    Entry.new(key: "settlement_transfer", model: "SettlementTransfer", client_type: "settlementTransfer", pool_method: :add_settlement_transfer, tracks_user: false, policy: "SettlementTransferPolicy"),
    Entry.new(key: "chore_roster",       model: "ChoreRoster",        client_type: "choreRoster",        pool_method: :add_chore_roster,        tracks_user: true,  policy: "ChoreRosterPolicy"),
    Entry.new(key: "chore",              model: "Chore",              client_type: "chore",              pool_method: :add_chore,               tracks_user: false, policy: "ChorePolicy"),
    Entry.new(key: "chore_assignment",   model: "ChoreAssignment",    client_type: "choreAssignment",    pool_method: :add_chore_assignment,    tracks_user: true,  policy: "ChoreAssignmentPolicy"),
    Entry.new(key: "workspace_invite", model: "WorkspaceInvite", client_type: "workspaceInvite", pool_method: :add_workspace_invite, tracks_user: false, policy: "WorkspaceInvitePolicy"),
    Entry.new(key: "expense_participant", model: "ExpenseParticipant", client_type: "expenseParticipant", pool_method: :add_expense_participant, tracks_user: true, policy: "ExpenseParticipantPolicy")
  ].freeze

  BY_KEY = TYPES.each_with_object({}) { |t, h| h[t.key] = t }.freeze
  BY_CLIENT_TYPE = TYPES.each_with_object({}) { |t, h| h[t.client_type] = t }.freeze
end
