# typed: true
# frozen_string_literal: true

# Central registry of all pool object types. Single source of truth used by
# Websocket::Listener, Sync::WorkspaceSync, and PoolSerializer.
module ObjectRegistry
  class Entry < T::Struct
    const :key, String
    const :model, String
    const :client_type, String
    const :pool_method, Symbol
    const :tracks_user, T::Boolean
  end

  TYPES = T.let(
    [
      Entry.new(key: "event",       model: "Event",                client_type: "event",      pool_method: :add_event,       tracks_user: true),
      Entry.new(key: "workspace",   model: "Workspace",            client_type: "workspace",  pool_method: :add_workspace,   tracks_user: false),
      Entry.new(key: "member",      model: "WorkspaceMembership",  client_type: "member",     pool_method: :add_member,      tracks_user: false),
      Entry.new(key: "date_poll",   model: "DatePoll",             client_type: "datePoll",   pool_method: :add_date_poll,   tracks_user: false),
      Entry.new(key: "date_range",  model: "DateRange",            client_type: "dateRange",  pool_method: :add_date_range,  tracks_user: false),
      Entry.new(key: "vote",        model: "Vote",                 client_type: "vote",       pool_method: :add_vote,        tracks_user: true),
      Entry.new(key: "rsvp",        model: "Rsvp",                 client_type: "rsvp",       pool_method: :add_rsvp,        tracks_user: true),
      Entry.new(key: "task_list",   model: "TaskList",             client_type: "taskList",   pool_method: :add_task_list,   tracks_user: true),
      Entry.new(key: "task_item",   model: "TaskItem",             client_type: "taskItem",   pool_method: :add_task_item,   tracks_user: true),
      Entry.new(key: "expense",     model: "Expense",              client_type: "expense",    pool_method: :add_expense,     tracks_user: true),
      Entry.new(key: "settlement",  model: "Settlement",           client_type: "settlement", pool_method: :add_settlement,  tracks_user: true),
      Entry.new(key: "settlement_transfer", model: "SettlementTransfer", client_type: "settlementTransfer", pool_method: :add_settlement_transfer, tracks_user: false),
      Entry.new(key: "chore_roster",       model: "ChoreRoster",        client_type: "choreRoster",        pool_method: :add_chore_roster,        tracks_user: true),
      Entry.new(key: "chore",              model: "Chore",              client_type: "chore",              pool_method: :add_chore,               tracks_user: false),
      Entry.new(key: "chore_assignment",   model: "ChoreAssignment",    client_type: "choreAssignment",    pool_method: :add_chore_assignment,    tracks_user: true)
    ].freeze,
    T::Array[Entry]
  )

  BY_KEY = T.let(
    TYPES.each_with_object({}) { |t, h| h[t.key] = t }.freeze,
    T::Hash[String, Entry]
  )
end
