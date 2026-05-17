# frozen_string_literal: true

# Central registry of all pool object types. Single source of truth used by
# Websocket::Listener, Sync::WorkspaceSync, and PoolSerializer.
#
# `audience` is used by WorkspaceSync to decide what's included in the
# workspace handshake:
#   :workspace — owned by the workspace; included in WorkspaceSync.
#   :user      — owned by a single user; not part of WorkspaceSync.
#                User-audience types may have `policy: nil` because the
#                recipient is the audience and there's no per-viewer
#                permission diff to compute.
#
# `topics:` declares broadcast routing as a proc `(obj) -> [Topic...]`.
# The Listener calls `entry.topics_for(obj)` after loading each object
# and dispatches to every returned topic. The default — when `topics:`
# is omitted — returns `[Topic.workspace(obj.workspace_id)]`, which
# covers most types; only the ones that need a join (chore, vote,
# date_range, expense_participant, settlement_transfer, chore_assignment,
# task_item) and the user-channel types (notification) spell out a
# custom proc.
module ObjectRegistry
  DEFAULT_TOPICS = ->(obj) { [Topic.workspace(obj.workspace_id)] }

  class Entry
    attr_reader :key, :model, :client_type, :tracks_user, :policy, :serializer_class, :audience

    def initialize(
      key:,
      model:,
      client_type:,
      tracks_user:,
      policy:,
      serializer_class:,
      audience: :workspace,
      topics: DEFAULT_TOPICS
    )
      @key = key
      @model = model
      @client_type = client_type
      @tracks_user = tracks_user
      @policy = policy
      @serializer_class = serializer_class
      @audience = audience
      @topics_proc = topics
    end

    def workspace_audience?
      @audience == :workspace
    end

    def user_audience?
      @audience == :user
    end

    def topics_for(obj)
      @topics_proc.call(obj)
    end
  end

  TYPES = [
    Entry.new(key: "event", model: "Event", client_type: "event", tracks_user: true, policy: "EventPolicy", serializer_class: EventSerializer),
    Entry.new(key: "workspace", model: "Workspace", client_type: "workspace", tracks_user: false, policy: "WorkspacePolicy", serializer_class: WorkspaceSerializer,
              topics: ->(workspace) { [Topic.workspace(workspace.id)] }
    ),
    # Member changes ride the default workspace topic. With the auth
    # handshake auto-subscribing each connection to every workspace its
    # user belongs to, the affected user's other sessions hear about
    # their own role changes via that same topic — no user-channel
    # duplication needed. Bootstrap for "user added to a new workspace"
    # is handled in the Listener (subscribes new connections + delivers
    # a WorkspaceSync).
    Entry.new(key: "member", model: "WorkspaceMembership", client_type: "member", tracks_user: false, policy: "MemberPolicy", serializer_class: MemberSerializer),
    Entry.new(key: "date_poll", model: "DatePoll", client_type: "datePoll", tracks_user: false, policy: "DatePollPolicy", serializer_class: DatePollSerializer,
              topics: ->(poll) {
                ws_id = DB[:events].where(id: poll.event_id).get(:workspace_id)
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "date_range", model: "DateRange", client_type: "dateRange", tracks_user: false, policy: "DateRangePolicy", serializer_class: DateRangeSerializer,
              topics: ->(range) {
                ws_id = DB[:date_polls]
                        .join(:events, id: :event_id)
                        .where(Sequel[:date_polls][:id] => range.date_poll_id)
                        .get(Sequel[:events][:workspace_id])
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "vote", model: "Vote", client_type: "vote", tracks_user: true, policy: "VotePolicy", serializer_class: Vote,
              topics: ->(vote) {
                ws_id = DB[:date_ranges]
                        .join(:date_polls, id: :date_poll_id)
                        .join(:events, id: Sequel[:date_polls][:event_id])
                        .where(Sequel[:date_ranges][:id] => vote.date_range_id)
                        .get(Sequel[:events][:workspace_id])
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "rsvp", model: "Rsvp", client_type: "rsvp", tracks_user: true, policy: "RsvpPolicy", serializer_class: Rsvp,
              topics: ->(rsvp) {
                ws_id = DB[:events].where(id: rsvp.event_id).get(:workspace_id)
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "task_list", model: "TaskList", client_type: "taskList", tracks_user: true, policy: "TaskListPolicy", serializer_class: TaskListSerializer),
    Entry.new(key: "task_item", model: "TaskItem", client_type: "taskItem", tracks_user: true, policy: "TaskItemPolicy", serializer_class: TaskItem,
              topics: ->(item) {
                ws_id = DB[:task_lists].where(id: item.task_list_id).get(:workspace_id)
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "expense", model: "Expense", client_type: "expense", tracks_user: true, policy: "ExpensePolicy", serializer_class: ExpenseSerializer,
              topics: ->(expense) {
                ws_id = DB[:events].where(id: expense.event_id).get(:workspace_id)
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "settlement", model: "Settlement", client_type: "settlement", tracks_user: true, policy: "SettlementPolicy", serializer_class: SettlementSerializer,
              topics: ->(settlement) {
                ws_id = DB[:events].where(id: settlement.event_id).get(:workspace_id)
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "settlement_transfer", model: "SettlementTransfer", client_type: "settlementTransfer", tracks_user: false, policy: "SettlementTransferPolicy", serializer_class: SettlementTransferSerializer,
              topics: ->(transfer) {
                ws_id = DB[:settlements]
                        .join(:events, id: :event_id)
                        .where(Sequel[:settlements][:id] => transfer.settlement_id)
                        .get(Sequel[:events][:workspace_id])
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "chore_roster", model: "ChoreRoster", client_type: "choreRoster", tracks_user: true, policy: "ChoreRosterPolicy", serializer_class: ChoreRosterSerializer,
              topics: ->(roster) {
                ws_id = DB[:events].where(id: roster.event_id).get(:workspace_id)
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "chore", model: "Chore", client_type: "chore", tracks_user: false, policy: "ChorePolicy", serializer_class: ChoreSerializer,
              topics: ->(chore) {
                ws_id = DB[:chore_rosters]
                        .join(:events, id: :event_id)
                        .where(Sequel[:chore_rosters][:id] => chore.chore_roster_id)
                        .get(Sequel[:events][:workspace_id])
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "chore_assignment", model: "ChoreAssignment", client_type: "choreAssignment", tracks_user: true, policy: "ChoreAssignmentPolicy", serializer_class: ChoreAssignment,
              topics: ->(assignment) {
                ws_id = DB[:chores]
                        .join(:chore_rosters, id: :chore_roster_id)
                        .join(:events, id: Sequel[:chore_rosters][:event_id])
                        .where(Sequel[:chores][:id] => assignment.chore_id)
                        .get(Sequel[:events][:workspace_id])
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "workspace_invite", model: "WorkspaceInvite", client_type: "workspaceInvite", tracks_user: false, policy: "WorkspaceInvitePolicy", serializer_class: WorkspaceInvite),
    Entry.new(key: "expense_participant", model: "ExpenseParticipant", client_type: "expenseParticipant", tracks_user: true, policy: "ExpenseParticipantPolicy", serializer_class: ExpenseParticipant,
              topics: ->(participant) {
                ws_id = DB[:expenses]
                        .join(:events, id: :event_id)
                        .where(Sequel[:expenses][:id] => participant.expense_id)
                        .get(Sequel[:events][:workspace_id])
                [Topic.workspace(ws_id)]
              }
    ),
    Entry.new(key: "notification", model: "Notification", client_type: "notification",
              tracks_user: true, policy: nil, serializer_class: NotificationSerializer,
              audience: :user,
              topics: ->(notification) { [Topic.user(notification.user_id)] }
    )
  ].freeze

  BY_KEY = TYPES.each_with_object({}) { |t, h| h[t.key] = t }.freeze
  BY_CLIENT_TYPE = TYPES.each_with_object({}) { |t, h| h[t.client_type] = t }.freeze
end
