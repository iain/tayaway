# Backend Object Sync

How the Ruby backend pushes changes to connected clients in real time, and how it answers the catch-up sync that runs whenever a client (re)connects. Companion to `doc/offline-support.md`, which covers the frontend half.

## The contract in one sentence

Every service that mutates a syncable row is responsible for telling everyone else: it records a `deleted_items` row for each removal so partial sync can find it, and it calls `Broadcaster` for each change so live clients hear about it.

If you skip either side of that, some clients see the change immediately and others only after a manual reload.

## The pieces

```
service ─► Broadcaster.object_changed/deleted ─► pg_notify
                                                    │
                                                    ▼
                                              Listener (LISTEN)
                                                    │
                                          PoolSerializer.add(...)
                                                    │
                              ConnectionManager.broadcast_to_workspace
                                                    │
                                          PermissionAttacher (per recipient)
                                                    │
                                                    ▼
                                                WebSocket
```

- **`Broadcaster`** (`app/services/broadcaster.rb`): two methods, `object_changed` and `object_deleted`. Sends a tiny JSON payload over `pg_notify` on channel `tayaway_objects`. Payload is just `workspaceId`, `objectType`, `objectId`, `action` — small enough to stay under Postgres' 8KB NOTIFY limit.
- **`Listener`** (`app/websocket/listener.rb`): a single background thread holds a dedicated DB connection in `LISTEN` mode. On each notification it looks the object up in `ObjectRegistry`, fetches the current row, runs it through `PoolSerializer`, and hands the message to `ConnectionManager`. Errors restart the listen loop after a delay; the connection is shared across all worker fibers so there's no per-request overhead.
- **`ObjectRegistry`** (`app/object_registry.rb`): the single source of truth for what's syncable. Each entry binds a registry key (`"task_item"`) to a model (`TaskItem`), a client-side `objectType` string (`"taskItem"`), a serializer, and a policy class. `Listener`, `WorkspaceSync`, and `PoolSerializer` all walk this table — adding a new syncable type is a single registration, not a hunt-and-peck across files.
- **`PoolSerializer`** (`app/serializers/pool_serializer.rb`): builds the `{ objects: [...] }` payload. When invoked from the listener it also collects the raw model and policy context for each object so `PermissionAttacher` can stamp per-recipient permissions onto the broadcast without reloading from the database.
- **`ConnectionManager`** (`app/websocket/connection_manager.rb`): tracks live WebSocket connections grouped by workspace. `broadcast_to_workspace` iterates every connection, runs `PermissionAttacher` for that recipient's membership, and writes the message.
- **`PermissionAttacher`** (`app/serializers/permission_attacher.rb`): the one place that merges policy-derived `permissions:` into a serialized object. Used at sync time and at broadcast time, so the two paths can never drift.
- **`Sync::WorkspaceSync`** (`app/services/sync/workspace_sync.rb`): handles the catch-up sync that runs when a client (re)connects. See "Partial sync" below.
- **`DeletedItems`** (`lib/deleted_items.rb`): a thin helper for bulk-inserting `deleted_items` rows. Use it for any cascade where you have a list of child IDs.

## Writing a service that mutates a syncable object

Three rules. Break any of them and a class of users will need to reload.

### 1. Broadcast every changed object

After a successful create or update, call `Broadcaster.object_changed(<registry_key>, id, workspace_id: ...)`. The registry key is the snake_case key from `ObjectRegistry`, not the camelCase client type — the listener uses it to look up the model.

```ruby
DB[:expenses].insert(id: expense_id, ...)
Broadcaster.object_changed("expense", expense_id, workspace_id: workspace_id)
```

The listener will fetch the current row and broadcast it to everyone in the workspace. You don't pass any payload — `Broadcaster` is the trigger, the listener is the source of truth.

### 2. Broadcast every cascaded child individually

A broadcast for a parent does **not** carry its children. If your service deletes a parent and the database FK-cascades the children, you still have to broadcast each child:

```ruby
DB.transaction do
  child_ids = DB[:task_items].where(task_list_id: list_id).select_map(:id)
  child_ids.each do |id|
    Broadcaster.object_deleted("task_item", id, workspace_id: workspace_id)
  end

  DB[:task_lists].where(id: list_id).delete   # FK cascade fires
  Broadcaster.object_deleted("task_list", list_id, workspace_id: workspace_id)
end
```

The frontend's `cascadeRemove` will usually clean up children locally as a safety net, but cascading client-side is best-effort. A service that creates or updates children — for example a revert flow that copies participants onto a new expense — has no client-side fallback and _must_ broadcast each child.

### 3. Record every deletion in `deleted_items`

Live clients hear the broadcast. A client that's offline (or a tab that was backgrounded long enough that the WebSocket dropped) catches up via partial sync, which reads the `deleted_items` table to find what disappeared during the gap. If you delete without recording, returning clients will keep stale objects in their pool indefinitely.

```ruby
DeletedItems.bulk_insert(workspace_id, "task_item", child_ids)
DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "task_list", object_id: list_id)
```

The retention window is 7 days (`Sync::WorkspaceSync::RETENTION_PERIOD`). A client whose `since` timestamp is older falls back to a full sync, so older `deleted_items` rows can be pruned by an out-of-band job without breaking correctness.

## Partial sync

`Sync::WorkspaceSync.call(workspace_id:, since:, membership:)` is what answers the WebSocket's catch-up request. It returns a `{ syncType, syncedAt, objects, deleted }` payload.

- If `since` is missing or older than the retention cutoff, sync runs in `"full"` mode: every object the membership can see, no `deleted` array.
- Otherwise it's `"partial"`: each registry type's `changed_since(workspace_id, since)` is called, and the `deleted_items` table is queried for removals in the same window.

Two non-obvious special cases:

- **Workspace is always included.** Adding a member doesn't bump the workspace row's `updated_at`, but the workspace's denormalized member list does change. Re-emitting the workspace on every partial sync keeps the client in sync.
- **All members are always included.** Member rows are needed to resolve `userId` references on the client even if no membership changed during the window.

## Permissions on broadcasts

Broadcasts go to every connection in the workspace. `PermissionAttacher` runs per-recipient and stamps a `permissions:` field onto each object based on the recipient's policy result — so the wire payload is the same data, but each connection sees a `permissions:` block that reflects what _that user_ can do.

For fan-out broadcasts (a parent serializer that pushes children — e.g. an expense pulling in its participants), the listener captures `policy_contexts` from `PoolSerializer` so the children get permissions computed at broadcast time without re-fetching.

A policy crash for one object is caught in `PermissionAttacher.attach_to_message`: that single object ships without a `permissions` key, the failure is logged with the object id and recipient membership id, and the rest of the broadcast still goes out. Real bugs (NoMethodError, ArgumentError) propagate at sync time so you find them in tests; only broadcast-side per-object failures are isolated.

## Adding a new syncable object type

1. Add a row to `ObjectRegistry::TYPES` with the model, serializer, and policy.
2. Implement `<Model>.changed_since(workspace_id, since)` so partial sync can find changed rows.
3. Implement `<Model>Serializer.serialize_batch` (or extend `PoolObjectSerializer` if it fits).
4. Implement `<Model>Policy` with at least the actions your routes enforce.
5. In every service that mutates the new type, follow the three rules above.
6. Bump `CACHE_VERSION` in `frontend/src/api/poolDb.ts` if the wire shape changes — clients with stale caches will reset and full-sync.
7. Add a `CASCADE_RULES` entry in `frontend/src/stores/objectPool.ts` if the new type is a parent — this is the client-side safety net, not a substitute for backend broadcasts.
