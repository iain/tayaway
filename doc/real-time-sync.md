# Real-Time Sync Architecture

This document describes Tayaway's real-time synchronization system, which keeps all connected clients in sync using WebSockets, PostgreSQL LISTEN/NOTIFY, and an object pool pattern.

## Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Client A  │     │   Client B  │     │   Client C  │
│ (Vue + Pool)│     │ (Vue + Pool)│     │ (Vue + Pool)│
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │ WebSocket
                           ▼
              ┌────────────────────────┐
              │   Connection Manager   │
              │   (Ruby Singleton)     │
              └───────────┬────────────┘
                          │
                          ▼
              ┌────────────────────────┐
              │      Listener          │◄──── pg_notify
              │  (Background Thread)   │
              └───────────┬────────────┘
                          │
                          ▼
              ┌────────────────────────┐
              │      PostgreSQL        │
              │   LISTEN/NOTIFY        │
              └───────────┬────────────┘
                          │
                          ▼
              ┌────────────────────────┐
              │     Broadcaster        │◄──── Service calls
              │   (pg_notify sender)   │
              └────────────────────────┘
```

## Components

### 1. Object Pool (Frontend)

**Location:** `frontend/src/stores/objectPool.ts`

The object pool is a client-side cache that stores all objects by type and ID. It provides:

- **Unified storage:** All objects (users, events, date ranges, votes, workspaces) stored in typed maps
- **Optimistic updates:** Pending changes are tracked separately and merged when reading
- **Server-authoritative merge:** When server data arrives, it's merged based on `updatedAt` timestamps

```typescript
// Storage structure
Map<ObjectType, Map<id, PoolObject>>

// Merge logic: server data wins if strictly newer
if (!existing || isNewer(obj.updatedAt, existing.updatedAt)) {
  typeMap.set(obj.id, obj)
}
```

**Key methods:**
- `importObjects(objects)` - Merge server objects into pool
- `get(type, id)` - Get object with pending updates merged
- `addPending(type, id, changes)` - Add optimistic update
- `remove(type, id)` - Delete object from pool

### 2. WebSocket Store (Frontend)

**Location:** `frontend/src/stores/websocket.ts`

Manages the WebSocket connection lifecycle and message handling.

**Connection flow:**
1. Client connects with session token: `ws://host/ws?token=<token>`
2. Server authenticates and sends `authenticated` message with workspace IDs
3. Server sends `sync` message with all objects for user's workspaces
4. Client sets `hasSynced = true` to indicate ready state

**Message types:**
```typescript
// Server → Client
{ type: "authenticated", userId: string, workspaceIds: string[] }
{ type: "sync", data: { objects: PoolObject[] } }
{ type: "broadcast", workspaceId: string, action: "update" | "delete", data: {...} }
{ type: "pong" }
{ type: "error", message: string }

// Client → Server
{ type: "ping" }
```

### 3. Broadcaster (Backend)

**Location:** `backend/app/services/broadcaster.rb`

Sends change notifications via PostgreSQL `pg_notify`. Called by service modules after database mutations.

```ruby
# Usage in services
Broadcaster.object_changed("event", event_id, workspace_id: workspace_id)
Broadcaster.object_deleted("vote", vote_id, workspace_id: workspace_id)
```

**Payload format (kept small for pg_notify's 8KB limit):**
```json
{
  "workspaceId": "uuid",
  "objectType": "event",
  "objectId": "uuid",
  "action": "update"
}
```

### 4. Listener (Backend)

**Location:** `backend/app/websocket/listener.rb`

Background thread that listens for PostgreSQL NOTIFY events, fetches full object data, and broadcasts to WebSocket clients.

**Flow:**
1. Receives minimal notification from `pg_notify`
2. Fetches full object from database
3. Serializes via `PoolSerializer`
4. Broadcasts to all connections in the workspace

**Special handling for related objects:**
When a vote changes, the parent date range's `voteIds` array also changes. The listener includes the parent date range in vote broadcasts:

```ruby
if object_type == "vote"
  date_range = DateRange.find(object.date_range_id)
  pool.add_date_range(date_range) if date_range
end
```

### 5. Connection Manager (Backend)

**Location:** `backend/app/websocket/connection_manager.rb`

Thread-safe singleton that tracks WebSocket connections and their workspace associations.

**Key methods:**
- `register(websocket, user_id)` - Register new connection
- `set_workspaces(connection_id, workspace_ids)` - Associate workspaces
- `broadcast_to_workspace(workspace_id, message)` - Send to all workspace members
- `unregister(connection_id)` - Clean up on disconnect

### 6. Pool Serializer (Backend)

**Location:** `backend/app/serializers/pool_serializer.rb`

Collects and serializes objects for API responses. Automatically includes related objects (deduped by type:id).

```ruby
pool = PoolSerializer.new
pool.add_event(event)  # Also adds user, date_ranges, votes
{ objects: pool.to_a }
```

## Data Flow Examples

### Creating a Vote

```
1. Client A creates vote (optimistic update to pool)
   └─► addPending("dateRange", id, { voteIds: [..., newId] })
   └─► set("vote", newVoteObject)

2. Client A sends POST /api/events/:id/votes

3. Server creates vote in database
   └─► DB[:votes].insert(...)
   └─► DB[:date_ranges].update(updated_at: now)  # Touch parent!
   └─► Broadcaster.object_changed("vote", vote_id, workspace_id: ws_id)

4. PostgreSQL sends NOTIFY to channel "tayaway_objects"

5. Listener receives notification
   └─► Fetches vote from database
   └─► Fetches parent date_range (for voteIds)
   └─► Serializes both via PoolSerializer
   └─► Broadcasts to workspace connections

6. All clients receive broadcast
   └─► importObjects([vote, dateRange])
   └─► Clears pending updates (server authoritative)
   └─► Updates pool with newer objects
```

### Deleting a Vote

```
1. Client sends DELETE /api/events/:id/votes/:vote_id

2. Server deletes vote
   └─► DB[:votes].delete(...)
   └─► DB[:date_ranges].update(updated_at: now)  # Touch parent!
   └─► Broadcaster.object_deleted("vote", vote_id, workspace_id: ws_id)
   └─► Broadcaster.object_changed("date_range", dr_id, workspace_id: ws_id)

3. Listener handles notifications
   └─► For delete: broadcasts { deleted: [{ objectType, id }] }
   └─► For date_range update: broadcasts updated date_range

4. Clients receive broadcasts
   └─► pool.remove("vote", vote_id)
   └─► pool.importObjects([dateRange])  # Updated voteIds
```

## Important Implementation Details

### Timestamp Comparison

The pool uses **strictly newer** (`>`) comparison for merging:

```typescript
function isNewer(a: string, b: string): boolean {
  return new Date(a).getTime() > new Date(b).getTime()
}
```

This means:
- If server timestamp equals client timestamp, object is **not** updated
- Pending updates are cleared regardless of timestamp comparison
- Parent objects must have their `updated_at` touched when child relationships change

### Touching Parent Timestamps

When child objects are added/removed, the parent's `updated_at` must be touched:

```ruby
# In votes/upsert.rb - when creating a vote
DB[:date_ranges].where(id: date_range.id).update(updated_at: now)

# In votes/delete.rb - when deleting a vote
DB[:date_ranges].where(id: date_range_id).update(updated_at: Time.now)
```

Without this, the broadcasted parent would have the same timestamp as the client's cached version, causing the merge to skip the update.

### WebSocket Flushing

WebSocket writes must be flushed for immediate delivery:

```ruby
connection.websocket.write(json_message)
connection.websocket.flush  # Required!
```

Without `flush()`, messages buffer and only send on pings or connection close.

## Object Types Registry

### Frontend (`frontend/src/types/pool.ts`)

```typescript
export const OBJECT_TYPES = [
  'user', 'event', 'dateRange', 'vote',
  'workspace', 'workspaceMembership'
] as const
```

### Backend (`backend/app/websocket/listener.rb`)

```ruby
OBJECT_TYPES = {
  "event" => { model: "Event", pool_method: :add_event },
  "user" => { model: "User", pool_method: :add_user },
  "date_range" => { model: "DateRange", pool_method: :add_date_range },
  "vote" => { model: "Vote", pool_method: :add_vote },
  "workspace" => { model: "Workspace", pool_method: :add_workspace },
  "workspace_membership" => { model: "WorkspaceMembership", pool_method: :add_workspace_membership }
}
```

## Adding a New Object Type

1. **Backend Model:** Create model with `to_api_hash` method
2. **Backend Serializer:** Add `add_<type>` method to `PoolSerializer`
3. **Backend Listener:** Add entry to `OBJECT_TYPES` registry
4. **Backend Services:** Call `Broadcaster.object_changed` after mutations
5. **Frontend Types:** Add to `OBJECT_TYPES` array and `ObjectTypeMap` interface
6. **Frontend Stores:** Create store that reads from object pool

## Debugging

### Check pool stats
```javascript
// In browser console
const pool = useObjectPoolStore()
console.log(pool.stats)  // { user: 5, event: 3, dateRange: 10, ... }
```

### Monitor WebSocket messages
```javascript
// In browser console - before connecting
const originalSend = WebSocket.prototype.send
WebSocket.prototype.send = function(data) {
  console.log('WS SEND:', data)
  return originalSend.apply(this, arguments)
}
```

### Check listener status
```ruby
# In Rails console
Websocket::Listener.running?  # => true/false
```
