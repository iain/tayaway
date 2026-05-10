# frozen_string_literal: true

# Central registry of all pool object types. Single source of truth used by
# Websocket::Listener, Sync::WorkspaceSync, and PoolSerializer.
#
# `audience` selects how the type is delivered:
#   :workspace — owned by the workspace; included in WorkspaceSync, broadcast
#                via Broadcaster.object_changed(..., workspace_id:). Most types
#                are workspace-audience.
#   :user      — owned by a single user; not part of WorkspaceSync, broadcast
#                via Broadcaster.object_changed(..., user_id:). User-audience
#                types may have `policy: nil` because the recipient is the
#                audience and there's no per-viewer permission diff to compute.
module ObjectRegistry
  class Entry
    attr_reader :key, :model, :client_type, :tracks_user, :policy, :serializer_class, :audience

    def initialize(
      key:,
      model:,
      client_type:,
      tracks_user:,
      policy:,
      serializer_class:,
      audience: :workspace
    )
      @key = key
      @model = model
      @client_type = client_type
      @tracks_user = tracks_user
      @policy = policy
      @serializer_class = serializer_class
      @audience = audience
    end

    def workspace_audience?
      @audience == :workspace
    end

    def user_audience?
      @audience == :user
    end
  end

  TYPES = [
    Entry.new(key: "event", model: "Event", client_type: "event", tracks_user: true, policy: "EventPolicy", serializer_class: EventSerializer),
    Entry.new(key: "workspace",   model: "Workspace",            client_type: "workspace",          tracks_user: false, policy: "WorkspacePolicy", serializer_class: WorkspaceSerializer),
    Entry.new(key: "member",      model: "WorkspaceMembership",  client_type: "member",             tracks_user: false, policy: "MemberPolicy", serializer_class: MemberSerializer),
    Entry.new(key: "date_poll",   model: "DatePoll",             client_type: "datePoll",           tracks_user: false, policy: "DatePollPolicy", serializer_class: DatePollSerializer),
    Entry.new(key: "date_range",  model: "DateRange",            client_type: "dateRange",          tracks_user: false, policy: "DateRangePolicy", serializer_class: DateRangeSerializer),
    Entry.new(key: "vote",        model: "Vote",                 client_type: "vote",               tracks_user: true,  policy: "VotePolicy", serializer_class: VoteSerializer),
    Entry.new(key: "rsvp",        model: "Rsvp",                 client_type: "rsvp",               tracks_user: true,  policy: "RsvpPolicy", serializer_class: RsvpSerializer),
    Entry.new(key: "task_list",   model: "TaskList",             client_type: "taskList",           tracks_user: true,  policy: "TaskListPolicy", serializer_class: TaskListSerializer),
    Entry.new(key: "task_item",   model: "TaskItem",             client_type: "taskItem",           tracks_user: true,  policy: "TaskItemPolicy", serializer_class: TaskItemSerializer),
    Entry.new(key: "expense",     model: "Expense",              client_type: "expense",            tracks_user: true,  policy: "ExpensePolicy", serializer_class: ExpenseSerializer),
    Entry.new(key: "settlement",  model: "Settlement",           client_type: "settlement",         tracks_user: true,  policy: "SettlementPolicy", serializer_class: SettlementSerializer),
    Entry.new(key: "settlement_transfer", model: "SettlementTransfer", client_type: "settlementTransfer", tracks_user: false, policy: "SettlementTransferPolicy", serializer_class: SettlementTransferSerializer),
    Entry.new(key: "chore_roster",       model: "ChoreRoster",        client_type: "choreRoster",        tracks_user: true,  policy: "ChoreRosterPolicy", serializer_class: ChoreRosterSerializer),
    Entry.new(key: "chore",              model: "Chore",              client_type: "chore",              tracks_user: false, policy: "ChorePolicy", serializer_class: ChoreSerializer),
    Entry.new(key: "chore_assignment",   model: "ChoreAssignment",    client_type: "choreAssignment",    tracks_user: true,  policy: "ChoreAssignmentPolicy", serializer_class: ChoreAssignmentSerializer),
    Entry.new(key: "workspace_invite", model: "WorkspaceInvite", client_type: "workspaceInvite",         tracks_user: false, policy: "WorkspaceInvitePolicy", serializer_class: WorkspaceInviteSerializer),
    Entry.new(key: "expense_participant", model: "ExpenseParticipant", client_type: "expenseParticipant", tracks_user: true, policy: "ExpenseParticipantPolicy", serializer_class: ExpenseParticipantSerializer),
    Entry.new(
      key: "notification", model: "Notification", client_type: "notification",
      tracks_user: true, policy: nil, serializer_class: NotificationSerializer,
      audience: :user
    )
  ].freeze

  BY_KEY = TYPES.each_with_object({}) { |t, h| h[t.key] = t }.freeze
  BY_CLIENT_TYPE = TYPES.each_with_object({}) { |t, h| h[t.client_type] = t }.freeze
end
