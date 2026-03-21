# Connectivity & Offline Guidelines

Rules for writing code that stays responsive on slow, flaky, or offline connections. Every developer and AI agent working on this codebase must follow these guidelines.

See `doc/offline-support.md` for how the offline system works. This document covers **what to do and what to avoid**.

## Core Principle

**The app must never feel stuck.** A user on a 2G connection opening the PWA from their homescreen should see their data within 1 second and be able to interact immediately. Network requests happen in the background — they never block rendering or interaction.

## Rules

### 1. Never Block Rendering on a Network Request

The router, layout, and page components must render from cache before any network call completes. Auth checks, data fetches, and WebSocket connections all happen in the background.

**Do:**
- Render from IndexedDB cache immediately on startup
- Show cached data with a subtle sync indicator
- Run auth verification in the background; redirect only on confirmed failure

**Don't:**
- `await fetch()` in `router.beforeEach` without a cached fallback
- Show a loading spinner while waiting for a network response when cached data exists
- Block component mounting on an API call

### 2. Every Fetch Must Have a Timeout

All HTTP requests must use an `AbortController` with a timeout. The default should be 15 seconds for mutations, 10 seconds for reads. Auth and WebSocket ticket requests use 5 seconds.

**Do:**
```typescript
const controller = new AbortController()
const timeout = setTimeout(() => controller.abort(), 15_000)
try {
  const response = await fetch(url, { signal: controller.signal })
} finally {
  clearTimeout(timeout)
}
```

**Don't:**
- Call `fetch()` without a signal
- Assume the network will respond in a reasonable time

### 3. Yield to the Event Loop in Loops

Any loop that processes more than ~50 items or makes sequential async calls must yield to the browser between iterations. Without yielding, scrolls, clicks, and animations freeze.

**Do:**
```typescript
for (const item of items) {
  await processItem(item)
  // Yield to browser between iterations
  await new Promise((r) => setTimeout(r, 0))
}
```

**Don't:**
- `for (const cmd of commands) { await execute(cmd) }` without yielding
- Process 1000+ pool objects synchronously without breaking into chunks
- Call `triggerRef()` inside a loop — collect changes and trigger once at the end

### 4. Batch Reactivity Updates

Vue reactivity triggers (`triggerRef`, `bumpVersion`) must fire once per logical operation, not once per object. A sync that imports 500 objects should cause one reactivity cycle, not 500.

**Do:**
- Collect all changes, then call `triggerRef()` once
- Use `bumpVersion(...changedTypes)` with the set of changed types
- Debounce `triggerRef()` with `queueMicrotask` if multiple sync messages arrive in rapid succession

**Don't:**
- Call `triggerRef()` inside a `for` loop
- Trigger reactivity for types that didn't change
- Let cascade deletes trigger per-object reactivity updates

### 5. Keep IndexedDB Off the Critical Path

IndexedDB writes are for durability, not for rendering. Never block user interaction on an IndexedDB transaction.

**Do:**
- Fire-and-forget for pool persistence writes (log errors, don't await)
- Use `requestIdleCallback` for non-urgent persistence
- Load cache meta (workspace ID, version) first, then stream objects progressively

**Don't:**
- `await poolDb.saveObjects(saves)` on the main interaction path
- Block `importObjects()` on a persistence flush
- Read all 5000 cached objects in one synchronous IndexedDB transaction on startup

### 6. WebSocket State Machine Must Be Bulletproof

The WebSocket connection state (`disconnected` → `connecting` → `authenticated`) must never get stuck. Every error path must reset state to `disconnected` so reconnection can proceed.

**Do:**
- Set `state.value = 'disconnected'` in every `catch` block and `finally` block
- Guard against concurrent connection attempts (check state before starting)
- Show the connection badge immediately when state leaves `authenticated`

**Don't:**
- Leave state at `connecting` after an error
- Assume `getWebSocketUrl()` will always resolve — it can timeout
- Silently swallow connection failures — at minimum log them

### 7. Degrade Gracefully, Don't Fail Silently

When something goes wrong on a slow connection, the user must know. Silent failures are worse than visible errors.

**Do:**
- Show "Offline" or "Reconnecting..." badge when the socket is down
- Show a toast when a queued command fails permanently
- Log connection failures to console with context (attempt count, close code, error message)

**Don't:**
- Swallow errors with empty `catch {}`
- Let a timeout pass without updating UI state
- Assume the user will notice that sync stopped working

### 8. Mutations Go Through the Command Queue

All domain object mutations must use `useMutation` and the command queue. This ensures offline queueing, optimistic UI, and automatic retry on reconnect.

**Do:**
- `useMutation().create()` / `.update()` / `.destroy()` for all CRUD
- Generate client-side UUIDs for new objects
- Handle `CommandQueuedError` gracefully (mutation will retry later)

**Don't:**
- Call `api.post()` directly from a store for domain mutations
- Assume the server will respond — always handle the queued case
- Skip optimistic updates ("it'll be fast enough") — it won't be on 2G

### 9. Test on Throttled Connections

Chrome DevTools Network Throttling is the minimum. Test these scenarios:

- **Slow 3G** (400ms RTT, 400kbps): App cold start, creating an event, switching workspaces
- **Offline → Online**: Queue 5 mutations offline, come back online, verify they all apply
- **Flaky** (50% packet loss): Open WebSocket, verify reconnection works repeatedly
- **PWA homescreen launch** on Slow 3G: Time from tap to interactive content

If the app freezes for more than 200ms or shows a spinner for more than 1 second when cached data exists, something is wrong.

## Quick Reference

| Operation | Timeout | Yield? | Cache? |
|-----------|---------|--------|--------|
| `/api/auth/me` | 5s | N/A | Should have SW cache |
| `/auth/ws-ticket` | 5s | N/A | No |
| Regular API reads | 10s | N/A | Consider SW cache |
| API mutations | 15s | N/A | Command queue |
| Command queue flush | 15s per cmd | Yes, between commands | N/A |
| `importObjects()` | N/A | Chunk if >500 objects | Debounced persistence |
| `replaceObjects()` | N/A | Chunk if >1000 objects | Atomic persistence |
| `cascadeRemove()` | N/A | Chunk if >100 removals | Debounced persistence |
| IndexedDB writes | N/A | `requestIdleCallback` | N/A |
| IndexedDB reads (startup) | N/A | Progressive load | N/A |
