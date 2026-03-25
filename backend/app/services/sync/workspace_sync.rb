# typed: true
# frozen_string_literal: true

module Sync
  # Service to synchronize workspace data. Supports full sync (all objects) and
  # partial sync (only objects changed since a given timestamp).
  #
  # Uses a single UNION ALL SQL query across all syncable tables to minimize
  # database round trips (1 query instead of N queries per object type).
  #
  # @example Full sync
  #   Sync::WorkspaceSync.call(workspace_id: "uuid")
  #
  # @example Partial sync
  #   Sync::WorkspaceSync.call(workspace_id: "uuid", since: Time.now - 60)
  module WorkspaceSync
    RETENTION_PERIOD = 7 * 24 * 60 * 60 # 7 days in seconds

    # Maps registry key to the batch pool method to use when adding items.
    BATCH_POOL_METHODS = T.let(
      {
        "event" => :add_events_batch,
        "date_poll" => :add_date_polls_batch,
        "date_range" => :add_date_ranges_batch,
        "settlement" => :add_settlements_batch,
        "member" => :add_members_batch
      }.freeze,
      T::Hash[String, Symbol]
    )

    # Columns that contain TIMESTAMPTZ values (returned as ISO8601 strings by row_to_json).
    # These are converted to Time objects before being passed to model from_row methods.
    TIMESTAMP_COLUMNS = T.let(
      %i[
        created_at updated_at closed_at deadline completed_at
        paid_at expires_at accepted_at last_reminded_at used_at
      ].freeze,
      T::Array[Symbol]
    )

    # Columns that contain DATE values (returned as "YYYY-MM-DD" strings by row_to_json).
    # These are converted to Date objects before being passed to model from_row methods.
    DATE_COLUMNS = T.let(
      %i[start_date end_date date birthday].freeze,
      T::Array[Symbol]
    )

    # Subquery templates for each object type.
    #
    # Each fragment SELECTs two columns:
    #   object_type TEXT  — the registry key for this type
    #   data        JSON  — all columns from the source table via row_to_json
    #
    # Bind parameters (in order): workspace_id (cast to UUID), since (timestamp).
    # Most types filter on `updated_at`; expense_participants filter on `created_at`.
    # workspace_invites add an extra `accepted_at IS NULL` guard.
    SUBQUERIES = T.let(
      [
        ["event", <<~SQL],
          SELECT 'event' AS object_type, row_to_json(t.*) AS data
          FROM events t
          WHERE t.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["workspace", <<~SQL],
          SELECT 'workspace' AS object_type, row_to_json(t.*) AS data
          FROM workspaces t
          WHERE t.id = ?::uuid AND t.updated_at > ?
        SQL
        ["member", <<~SQL],
          SELECT 'member' AS object_type, row_to_json(t.*) AS data
          FROM workspace_memberships t
          WHERE t.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["date_poll", <<~SQL],
          SELECT 'date_poll' AS object_type, row_to_json(t.*) AS data
          FROM date_polls t
          JOIN events e ON e.id = t.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["date_range", <<~SQL],
          SELECT 'date_range' AS object_type, row_to_json(t.*) AS data
          FROM date_ranges t
          JOIN date_polls dp ON dp.id = t.date_poll_id
          JOIN events e ON e.id = dp.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["vote", <<~SQL],
          SELECT 'vote' AS object_type, row_to_json(t.*) AS data
          FROM votes t
          JOIN date_ranges dr ON dr.id = t.date_range_id
          JOIN date_polls dp ON dp.id = dr.date_poll_id
          JOIN events e ON e.id = dp.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["rsvp", <<~SQL],
          SELECT 'rsvp' AS object_type, row_to_json(t.*) AS data
          FROM rsvps t
          JOIN events e ON e.id = t.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["task_list", <<~SQL],
          SELECT 'task_list' AS object_type, row_to_json(t.*) AS data
          FROM task_lists t
          WHERE t.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["task_item", <<~SQL],
          SELECT 'task_item' AS object_type, row_to_json(t.*) AS data
          FROM task_items t
          JOIN task_lists tl ON tl.id = t.task_list_id
          WHERE tl.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["expense", <<~SQL],
          SELECT 'expense' AS object_type, row_to_json(t.*) AS data
          FROM expenses t
          JOIN events e ON e.id = t.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["expense_participant", <<~SQL],
          SELECT 'expense_participant' AS object_type, row_to_json(t.*) AS data
          FROM expense_participants t
          JOIN expenses ex ON ex.id = t.expense_id
          JOIN events e ON e.id = ex.event_id
          WHERE e.workspace_id = ?::uuid AND t.created_at > ?
        SQL
        ["settlement", <<~SQL],
          SELECT 'settlement' AS object_type, row_to_json(t.*) AS data
          FROM settlements t
          JOIN events e ON e.id = t.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["settlement_transfer", <<~SQL],
          SELECT 'settlement_transfer' AS object_type, row_to_json(t.*) AS data
          FROM settlement_transfers t
          JOIN settlements s ON s.id = t.settlement_id
          JOIN events e ON e.id = s.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["chore_roster", <<~SQL],
          SELECT 'chore_roster' AS object_type, row_to_json(t.*) AS data
          FROM chore_rosters t
          JOIN events e ON e.id = t.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["chore", <<~SQL],
          SELECT 'chore' AS object_type, row_to_json(t.*) AS data
          FROM chores t
          JOIN chore_rosters cr ON cr.id = t.chore_roster_id
          JOIN events e ON e.id = cr.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["chore_assignment", <<~SQL],
          SELECT 'chore_assignment' AS object_type, row_to_json(t.*) AS data
          FROM chore_assignments t
          JOIN chores c ON c.id = t.chore_id
          JOIN chore_rosters cr ON cr.id = c.chore_roster_id
          JOIN events e ON e.id = cr.event_id
          WHERE e.workspace_id = ?::uuid AND t.updated_at > ?
        SQL
        ["workspace_invite", <<~SQL]
          SELECT 'workspace_invite' AS object_type, row_to_json(t.*) AS data
          FROM workspace_invites t
          WHERE t.workspace_id = ?::uuid AND t.updated_at > ? AND t.accepted_at IS NULL
        SQL
      ].freeze,
      T::Array[[String, String]]
    )

    class << self
      extend T::Sig

      sig do
        params(workspace_id: T.any(String, UUID), since: T.nilable(Time))
          .returns(T::Hash[Symbol, T.untyped])
      end
      def call(workspace_id:, since: nil)
        cutoff = T.cast(Time.now - RETENTION_PERIOD, Time)
        full = since.nil? || since < cutoff
        effective_since = full ? Time.at(0) : T.must(since)

        synced_at = Time.now
        workspace = Workspace.find(workspace_id)
        return empty_response(synced_at, full ? "full" : "partial") unless workspace

        pool = PoolSerializer.new(workspace_id: workspace_id)

        # Always include workspace so memberIds stays current on partial syncs
        # (adding a member doesn't update the workspace's updated_at)
        pool.add_workspace(workspace)

        # Single UNION ALL query fetches all changed objects across all types
        rows_by_type = fetch_changed_rows(workspace_id.to_s, effective_since)

        ObjectRegistry::TYPES.each do |entry|
          rows = rows_by_type[entry.key]
          next if rows.nil? || rows.empty?

          model = Object.const_get(entry.model)
          items = rows.map { |row| model.send(:from_row, row) }

          batch_method = BATCH_POOL_METHODS[entry.key]
          if batch_method
            pool.send(batch_method, items)
          else
            items.each { |item| pool.send(entry.pool_method, item) }
          end
        end

        # Include all members so the frontend can resolve userId references
        pool.add_members_batch(WorkspaceMembership.for_workspace(workspace_id))

        deleted = if full
                    []
                  else
                    DB[:deleted_items]
                      .where(workspace_id: workspace_id)
                      .where(Sequel.lit("deleted_at > ?", effective_since))
                      .select(:object_type, :object_id)
                      .map { |row| { objectType: row[:object_type], id: row[:object_id].to_s } }
                  end

        {
          syncType: full ? "full" : "partial",
          syncedAt: synced_at.iso8601(3),
          objects: pool.to_a,
          deleted: deleted
        }
      end

      private

      sig { params(synced_at: Time, sync_type: String).returns(T::Hash[Symbol, T.untyped]) }
      def empty_response(synced_at, sync_type)
        {
          syncType: sync_type,
          syncedAt: synced_at.iso8601(3),
          objects: [],
          deleted: []
        }
      end

      # Executes a single UNION ALL query across all syncable tables and returns
      # rows grouped by object type key. Each row's JSON data hash is converted
      # to symbol keys with timestamps and dates coerced to native Ruby types,
      # ready for the model's from_row method.
      sig do
        params(workspace_id: String, since: Time)
          .returns(T::Hash[String, T::Array[T::Hash[Symbol, T.untyped]]])
      end
      def fetch_changed_rows(workspace_id, since)
        sql_parts = []
        binds = []

        SUBQUERIES.each do |_key, sql|
          sql_parts << sql.strip
          binds.push(workspace_id, since)
        end

        union_sql = sql_parts.join("\nUNION ALL\n")

        DB.fetch(union_sql, *binds).each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, groups|
          groups[row[:object_type].to_s] << coerce_json_row(T.unsafe(row[:data]))
        end
      end

      # Converts a row_to_json hash (string keys, JSON primitive types) into the
      # symbol-keyed hash with native Ruby types that model from_row methods expect.
      # Timestamp strings are parsed to Time; date strings are parsed to Date.
      sig { params(json_row: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def coerce_json_row(json_row)
        json_row.each_with_object({}) do |(key, value), result|
          sym = key.to_sym
          result[sym] = if value.nil?
                          nil
                        elsif TIMESTAMP_COLUMNS.include?(sym) && value.is_a?(String)
                          Time.parse(value)
                        elsif DATE_COLUMNS.include?(sym) && value.is_a?(String)
                          Date.parse(value)
                        else
                          value
                        end
        end
      end
    end
  end
end
