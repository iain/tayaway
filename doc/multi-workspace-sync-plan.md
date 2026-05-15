# Multi-workspace sync plan

## Goal

Switching workspaces does a partial sync of *that* workspace's data into a
per-workspace local cache (no pre-emptive sync of anything else). Personal data
— your own memberships, the workspace rows you belong to, your notifications —
streams to your session regardless of which workspace is currently active.

## Why this is needed

Workspace support predates per-user object syncing. Today the WebSocket
listener routes by workspace audience only (notifications are the lone
user-audience exception), and `switchWorkspace` clears the in-memory pool and
the entire IndexedDB cache before re-syncing the new workspace from scratch.
Two consequences fall out of that:

1. Personal cross-workspace events — your own role changing in another
   workspace, being removed from a workspace, a workspace being renamed —
   never reach a session subscribed to a different workspace. The user only
   sees them on next switch.
2. Switching back to a workspace pays a full re-sync, even though almost all
   of that workspace's data has been seen before.

## Shape of the solution

- One active WebSocket subscription, partial-sync on switch via the existing
  `since` cursor mechanism.
- A user-audience channel for personal data (your own memberships, workspace
  rows you belong to, notifications) so cross-workspace personal events arrive
  regardless of active workspace.
- IndexedDB segmented per workspace, with one `syncedAt` cursor per workspace.
  Unbounded cache for now; quota-error-driven eviction only.
- In-memory pool segmented internally (`Map<workspaceId, Pool>` plus a
  personal pool) behind a `currentObjects` facade so existing selectors don't
  change.
- Every pooled object tagged with `workspaceId` at the WebSocket boundary,
  asserted invariant in `mergeObject`.
- Cached snapshot renders immediately on switch with a subtle "syncing"
  indicator until the partial sync resolves; never block UI.
- Command queue tags each command with its target workspace so replays after
  switching don't cross-contaminate.

## Personal data

Personal data is delivered to the user's connections regardless of which
workspace any one tab has active. Scope:

- The current user's own `WorkspaceMembership` rows across all their
  workspaces.
- The `Workspace` row for every workspace the current user belongs to.
- Notifications (already user-audience today — no change).

Notification *preferences* stay out of the pool: they're configuration with a
different lifecycle, accessed via the settings API.

A membership change fires two broadcasts: workspace-audience for the team
view, user-audience for the affected user. Frontend dedupes via the existing
newer-`updatedAt`-wins merge.

## Marquee e2e test

Two browsers, two users in two shared workspaces. Browser 1 sits on workspace
A. Browser 2, in workspace B, changes Browser 1's role in B. Browser 1's
workspace switcher reflects the change without switching. Browser 1 then
switches to B; the partial sync arrives, role is already current, cached pool
shows immediately (assert via DOM appearing before network roundtrip).

Keep this test red until the whole thing lands; back-fill the per-phase tests
below as each phase comes up green.

## Phase 1 — Backend: personal-audience broadcasts

**Failing test first:** an integration spec that mutates a
`WorkspaceMembership` and asserts the affected user's connection receives a
user-audience message even when subscribed to a different workspace.

- Extend `Broadcaster.object_changed` so membership changes fire two
  broadcasts: workspace-audience (existing, for the team view) **and**
  user-audience to the affected `user_id`.
- Same for `Workspace` row changes: workspace-audience (existing) **and**
  user-audience to every member.
- Listener already supports per-user fanout
  (`connection_manager.broadcast_to_user`) — no infra change.
- Add `Sync::PersonalSync` returning `{ workspaces, memberships }` for the
  authenticated user. Called once at handshake, before any workspace sync.
- Retire the existing workspace-selector summary message; the personal sync
  replaces it.

**Done when:** marquee test sees the personal-channel update arrive at the
client, but Browser 1's UI doesn't render it yet (frontend not wired).

## Phase 2 — Frontend: personal-pool semantics

**Failing test first:** a unit spec on `objectPool` asserting that an object
classified as personal (`workspace`, `notification`, or the current user's
own `member` row) survives `clearExcept`, and that other people's
memberships do not.

- Add `isPersonalObject(obj, currentUserId)` predicate routing notifications,
  workspace rows, and the user's own membership rows to "personal" status.
- Modify `clearExcept` so personal objects are preserved regardless of
  `keepTypes`. Workspace data still wipes on switch (today's behavior, until
  Phase 4 segments by workspace).
- Pool reads `currentUserId` from `useAuthStore`; tests mock it.

**Done when:** existing tests still pass; personal objects survive workspace
switches; selectors don't change.

Per-workspace segmentation of the workspace data (the
`Map<workspaceId, Pool>` structural change) is deferred to Phase 4 where
sync-on-switch needs it. Doing both in one phase made for too much surgery.

## Phase 3 — Frontend: per-workspace IndexedDB

**Failing test first:** a unit spec on `poolDb` that writes objects for two
workspaces and reads them back independently, with independent `syncedAt`
cursors.

- Re-key the cache from one flat store to `workspace:<id>` segments plus a
  `personal` segment.
- One `syncedAt` cursor per workspace in the meta store.
- `loadFromCache()` hydrates the current workspace's pool plus the personal
  pool on cold start.
- Remove the wholesale `clearAll()` on switch — caches now persist.

**Done when:** restart preserves every visited workspace's data; cold start
hydrates immediately for the last-active workspace.

## Phase 4 — Sync on switch (the visible win)

**Failing test first:** a unit spec asserting that `switchWorkspace`
hydrates the new workspace's IndexedDB cache into the pool so a switch-back
shows data before the partial sync response arrives.

- `switchWorkspace` clears in-memory workspace data (personal data
  survives via Phase 2) and triggers an async hydration from the new
  workspace's IndexedDB scope. The hydration sets `hasCachedData=true`
  so the full-page loader doesn't flash.
- `sendSwitchWorkspace` already sends the workspace's stored `syncedAt`
  cursor (Phase 3); server runs `Sync::WorkspaceSync` with `since:` →
  partial sync (or full if no cursor / cache too stale).
- Partial sync deltas merge into the existing in-memory pool via the
  existing `handleSync` path.
- The full structural in-memory `Map<workspaceId, Pool>` refactor is
  deliberately *not* done — cache hydration on switch achieves the same
  visible win (instant render on switch-back) with much less surgery.
  The cost is one extra IndexedDB round-trip per switch (~50ms typical).

Deferred to a follow-up:

- Subtle "syncing" indicator (pulse on the workspace name) until the
  partial sync resolves.
- Workspace-id invariant assertion in `mergeObject` — defensive code
  with no current failure mode now that personal vs workspace routing
  is explicit at the persistence layer.

**Done when:** unit test confirms the new workspace's cache hydrates
into the pool on switch; full-page loader is suppressed when cached
data is available.

## Phase 5 — Command queue per workspace

**Failing test first:** queue a mutation against workspace A while offline,
switch to B, come online — the mutation replays against A, not B.

- Tag each queued command with `workspaceId` at enqueue time (from
  `currentWorkspaceId` when the mutation was issued).
- On replay, route each command to its tagged workspace; commands for
  non-current workspaces still go out over the same HTTP API (the backend
  doesn't care which workspace is "active" for the connection — it cares
  about the request).

**Done when:** offline mutations across workspace switches don't
cross-contaminate.

## Phase 7 — Cross-workspace unread badges

**Failing test first:** an e2e test where Browser 1 (on workspace A) receives
a notification targeting workspace B; without switching, the workspace
selector shows an unread indicator on B. Marking the notification read clears
the indicator. Depends on Phases 1 + 2 (personal channel + personal pool).

- Notifications are already user-audience and carry `workspace_id`, so no new
  broadcast plumbing is needed.
- Extend `Sync::PersonalSync` to include the user's recent notification
  backlog (capped — most-recent N or last X days) so badges hydrate on cold
  start, not just from broadcasts received after connect.
- Frontend derives `unreadCountByWorkspace` from the notification pool
  (`personalObjects` filtered by `readAt == null`, grouped by `workspaceId`).
  No new object type; derived state.
- Render a dot/count in the workspace selector.
- Read state already round-trips via notification updates on the
  user-audience channel — no extra wiring.

**Done when:** badges reflect cross-workspace unread state live on every
session, with no extra round-trips beyond the existing notification path.

## Phase 6 — UX edges

- **You're removed from the workspace you're viewing** — done. A watcher on
  `allWorkspaces` redirects to the first remaining workspace, or clears
  `currentWorkspaceId` (and the localStorage marker) if no workspaces
  remain. Guarded against cold start: only acts once an authoritative
  workspace list has been observed.
- **Notifications referencing uncached workspaces** — moot. Workspace rows
  the user belongs to live in the personal pool and are always cached, so
  notification cards can always resolve a workspace name.
- **Quota eviction** — deferred. Build only when telemetry shows users
  hitting IndexedDB limits; the unbounded cache covers normal use.

## Sequencing

- **Parallel:** Phase 1 (backend) and Phase 2 (frontend pool refactor) —
  they don't touch each other.
- **Then:** Phase 3 (IndexedDB) → Phase 4 (sync-on-switch) →
  Phase 5 (command queue) → Phase 6 (edges).
- **Phase 7 (unread badges)** can land any time after Phases 1 + 2.
- Phase 5 must land before users start switching across queued mutations in
  the wild, so if Phase 4 ships behind a flag, Phase 5 ships with it.

## Out of scope (explicit non-goals)

- LRU eviction beyond the quota-error path.
- Subscribing to multiple workspaces simultaneously.
- Moving `UserNotificationPreference` into the pool.
