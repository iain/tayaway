# Offline Support

Tayaway works offline. Mutations queue to IndexedDB when the network is unavailable, the object pool is cached locally for instant startup, and partial sync minimizes data transfer on reconnect.

## Design Principles

**Write-ahead persistence.** Every mutation is written to IndexedDB before the network request fires. If the browser crashes mid-request, the command survives and retries on next load.

**Optimistic UI.** The pool updates immediately when the user acts — creates insert a temp object, updates apply pending changes, deletes remove the object. The user never waits for a server round-trip to see their change.

**Server-authoritative merge.** When the server responds (via API or WebSocket), it replaces optimistic state. `importObjects()` compares timestamps — strictly newer wins. A full sync clears all pending updates.

**Client-generated IDs.** `crypto.randomUUID()` lets the client create objects without a server round-trip for IDs. The server accepts client-provided UUIDs on create.

**Network errors are retryable, server errors are not.** A `TypeError` from `fetch()` or `navigator.onLine === false` means "try again later." A 4xx/5xx is permanently removed from the queue and surfaced to the user via notification.

**FIFO ordering.** Commands execute in creation order, preventing consistency issues like deleting an object before it's created.

**Debounced persistence.** Pool writes to IndexedDB are batched at 500ms intervals to avoid excessive I/O during rapid sync.

## How It Works

A mutation flows through three layers: optimistic pool update, command queue, and persistence.

When the user creates an event, for example, the events store generates a UUID and builds a temp object. `useMutation().create()` inserts it into the object pool immediately, then calls `commandQueue.enqueue()` which writes the command to IndexedDB and attempts the HTTP request. If the request succeeds, the command is removed from IndexedDB and the server response replaces the temp object. If the network is down, the command stays in IndexedDB, a `CommandQueuedError` is thrown, and the temp object remains visible in the UI.

Meanwhile, `usePoolPersistence` listens for pool changes and writes them to a separate IndexedDB database (the pool cache). On next app load, the cache is restored so the user sees their data instantly — before the WebSocket even connects.

When the browser comes back online, two things happen in parallel: the command queue flushes pending mutations sequentially, and the WebSocket reconnects and requests a partial sync using the last known `syncedAt` timestamp.

## Command Queue

**Files:** `stores/commandQueue.ts`, `api/commandDb.ts`

### Enqueue

`enqueue(method, path, body)` persists the command to IndexedDB first, then fires the HTTP request. On success, the command is removed. On network error, `CommandQueuedError` is thrown and the command remains for later retry. On server error, the command is removed and the error rethrown.

### Queue processing

Triggered by the browser `online` event or WebSocket re-authentication. Reads all pending commands from IndexedDB ordered by `createdAt`, executes each sequentially. Network errors halt processing (still offline). Server errors are logged via notification and skipped — processing continues with the next command.

### Network detection

```typescript
function isNetworkError(e: unknown): boolean {
  if (!(e instanceof TypeError)) return false
  if (!navigator.onLine) return true
  const msg = e.message.toLowerCase()
  return msg.includes('fetch') || msg.includes('network')
}
```

## Optimistic Updates

**File:** `composables/useMutation.ts`

Four patterns, all returning `MutationResult<T>` — either `{ queued: false, data }` or `{ queued: true }`:

| Method    | Before request                    | On success            | On queued            | On error                      |
| --------- | --------------------------------- | --------------------- | -------------------- | ----------------------------- |
| `create`  | `pool.set(tempObject)`            | Server replaces temp  | Temp stays           | Temp removed                  |
| `update`  | `pool.addPending(type, id, diff)` | Server clears pending | Pending stays        | Pending removed               |
| `destroy` | `pool.remove(type, id)`           | Object stays removed  | Object stays removed | Object restored from snapshot |
| `mutate`  | (none)                            | Returns data          | Returns queued       | Rethrows                      |

### Pending update merging

`pool.get(type, id)` returns server data with all pending changes merged on top:

```typescript
return pending.reduce((merged, update) => ({ ...merged, ...update.changes }), {
  ...server,
})
```

Components read from the pool normally and see optimistic state transparently.

## Pool Persistence

**Files:** `api/poolDb.ts`, `composables/usePoolPersistence.ts`

The object pool is cached in IndexedDB (`tayaway-pool-cache`) with three stores:

| Store            | Contents                                        |
| ---------------- | ----------------------------------------------- |
| `objects`        | All pool objects, keyed by `type:id`            |
| `meta`           | `workspaceId`, `syncedAt`, `cacheVersion`       |
| `pendingUpdates` | Optimistic updates awaiting server confirmation |

### Startup

`loadFromCache()` checks that the cached `workspaceId` and `CACHE_VERSION` match. If so, objects and pending updates are restored into the pool, `hasCachedData` is set to `true` (app renders immediately), and the `syncedAt` timestamp is restored for partial sync.

### Writing

`startPersisting()` subscribes to pool change callbacks. Full syncs trigger an atomic `replaceAll()`. Incremental changes (imports, sets, removes) are debounced at 500ms.

### Cache invalidation

`CACHE_VERSION` (currently 8) is bumped when the sync protocol changes. Mismatch clears the cache and forces a full sync.

## WebSocket Reconnection

**File:** `stores/websocket.ts`

### Triggers

- **Socket close:** 1-second delay, then reconnect
- **Browser online event:** Immediate reconnect
- **User click:** Connection badge in the header triggers `reconnect()`

### Partial sync

The client includes `since=<timestamp>` when connecting or switching workspaces. The server responds with `syncType: 'partial'` containing only objects modified after that timestamp, plus a `deleted` array for removals. Missing or stale `since` falls back to `syncType: 'full'`.

After sync, the new `syncedAt` is stored in memory and persisted to IndexedDB.

Partial sync covers workspace-audience objects only. Per-user types (e.g. notifications) live in the same pool but ride a separate per-user broadcast path; a client that missed broadcasts while offline catches up on the next load via the type's own REST endpoint (e.g. `GET /api/notifications`).

### Queue flush

On WebSocket authentication, `commandQueue.processQueue()` is called to flush any offline mutations.

## Cascade Deletes

When the pool removes an object — whether from a WebSocket delete, a partial-sync `deleted` entry, or an optimistic `destroy` — `cascadeRemove` (in `stores/objectPool.ts`) recursively removes dependents using `CASCADE_RULES`:

```
event ─┬─ datePoll ── dateRange ── vote
       ├─ rsvp
       ├─ expense ── expenseParticipant
       ├─ settlement ── settlementTransfer
       └─ choreRoster ── chore ── choreAssignment

taskList ── taskItem
```

The cascade is for client resilience: it keeps the local pool consistent even if a backend service forgets to enumerate children. Backend services are still required to broadcast each deleted child individually and record each one in `deleted_items` so a client returning via partial sync sees the same removals — see `doc/backend-sync.md`.

## Service Worker

**Files:** `vite.config.ts`, `registerSW.ts`

Vite PWA with Workbox caches static assets for offline access. `registerType: 'prompt'` shows a toast notification when a new service worker is available, letting the user choose when to reload. The app also checks for SW updates every 60 minutes and on tab visibility change (throttled to 30 seconds). Navigation requests use `NetworkFirst` runtime caching with a 3-second timeout.

## UI Indicators

**File:** `layouts/AuthenticatedLayout.vue`

| Condition                                 | UI                                                        |
| ----------------------------------------- | --------------------------------------------------------- |
| `!hasSynced && !hasCachedData`            | Full-screen loading spinner                               |
| `!hasSynced && hasCachedData`             | App renders from cache (no spinner)                       |
| `!isOnline`                               | "Offline" badge (gray dot) — clickable to retry           |
| `wsState !== 'authenticated' && isOnline` | "Server offline" badge (amber dot) — clickable to retry   |
| `pendingCount > 0 && !isOnline`           | Floating toast: "N pending change(s)" at bottom of screen |
