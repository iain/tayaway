# Sync engine spec

**Status: draft.** Principles are agreed. Guarantees and scenarios were seeded from the existing docs and extended with an in-depth prior-art review ([prior-art.md](prior-art.md), 2026-11-28); they are accepted as the target but open questions remain. They describe where the engine should be, not where it is today. Open questions are collected at the end and referenced inline as `OQ-n`.

This is the normative description of the sync engine: what it promises, to whom, and what it deliberately doesn't do. It does not describe how the engine is built. Implementation notes belong in separate docs that link back here.

## How to use this document

- **Changing the engine:** go through the guarantees in the areas you touch. Every change should leave each guarantee at least as well covered as before.
- **Adding a feature:** check whether one of the scenarios covers it. If none does, add a scenario. If the scenario needs a guarantee that doesn't exist, that's a spec change, not just a feature.
- **Writing tests:** tag tests with the IDs they cover (see [Coverage](#coverage)).

### Identifiers

Every principle, guarantee and scenario has a stable ID:

| Kind | Format | Example |
|---|---|---|
| Principle | `SYNC-P-<n>` | `SYNC-P-1` |
| Guarantee | `SYNC-G-<area><nn>` | `SYNC-G-302` |
| Scenario | `SYNC-S-<nnn>` | `SYNC-S-004` |
| Open question | `OQ-<n>` | `OQ-3` |

Rules:

- An ID is defined by a heading that starts with it: `#### SYNC-G-302: Title`. The coverage tooling parses exactly that pattern.
- IDs are never reused or renumbered. Titles may be reworded. A dropped guarantee stays in the document with `Status: retired` and a one-line reason.
- Guarantee numbers are the area number followed by two digits: durability is area 1 (`SYNC-G-101`), transparency is area 10 (`SYNC-G-1001`). Related IDs stay together, and adding one never renumbers the others.
- Open questions are temporary and not referenced from tests.

## Terminology

| Term | Meaning |
|---|---|
| **Server** | The authoritative backend. Its database state is the truth. |
| **Client** | One running instance of the app: a browser tab or an installed PWA. A user can have several clients. |
| **Object** | A syncable record with a type and an ID. The engine knows nothing about what types mean. |
| **Mutation** | A user's intent to change objects, issued by a client. Called a *command* once it is queued. |
| **Local state** | What the client shows: server state as last received, with the client's own unconfirmed mutations applied. |
| **Pending** | A mutation that is applied locally but not yet confirmed by the server. |
| **Confirmed** | The server has applied the mutation, and the client has received server state that includes it. |
| **Rejected** | The server has refused the mutation permanently (validation, permissions, missing object). Not the same as a network failure, an overload response or an expired session, which are retried. |
| **Live update** | A change pushed by the server to connected clients as it happens. |
| **Catch-up sync** | The exchange that brings a (re)connecting client up to date with everything it missed. |
| **Cursor** | The server-issued token that marks how far a client has caught up. Opaque to the client (`SYNC-G-318`). |
| **Quiescent** | No client is issuing mutations and all queues are empty. Used to state convergence. |
| **Reset** | Discarding local server state and rebuilding it from scratch. Causes include: an incompatible cache or schema version, a client behind the server's retention window, a cursor the server doesn't recognise or that is ahead of it (server restored from a backup, rebuilt database), detected divergence, lost local storage, a server instruction, and the user's own request. |
| **Operator** | A maintainer of the app, as opposed to a user. |

## Principles

The few rules everything else is derived from. When a guarantee and a principle seem to conflict, the principle wins and the guarantee gets rewritten.

Status: agreed (2026-11-28; `SYNC-P-8` and the online-only exception to `SYNC-P-1` added the same day).

#### SYNC-P-1: The network is optional

The app is fully usable without a connection, for everything a user is allowed to do, except actions explicitly declared online-only (`SYNC-G-706`). Connectivity only affects *when* other people see changes, never *whether* the user can work.

#### SYNC-P-2: Local first, server authoritative

The user's actions take effect locally right away. The server decides the final order and the final outcome. When the two disagree, the server wins, and the client shows how it got there.

#### SYNC-P-3: Never lose work silently

A change the user made is either applied on the server or explicitly reported to the user as not applied, with the reason. There is no third outcome.

#### SYNC-P-4: Never surprised

At any moment the user can tell what is confirmed, what is still pending, what failed, and whether what they are looking at might be out of date. When someone else's change replaces what the user saw, the user can tell that it happened. See [Never surprised](#never-surprised).

#### SYNC-P-5: Online means in sync

While connected, every client converges to server state within a bounded time (`OQ-6`) without any user action. Reloading the page never shows something the live app didn't.

#### SYNC-P-6: The engine knows no domain

The engine syncs typed objects. Everything specific to a type (relationships, cascades, merge rules, permissions, online-only actions) is supplied as registration data. No engine code mentions events, lists or any other product concept.

#### SYNC-P-7: Order comes from the server, not from clocks

The engine never decides correctness by comparing timestamps from different machines. Client clocks are for display only. (Prior art: Linear, Replicache, Figma, PowerSync, see `OQ-1` and `OQ-2`.)

#### SYNC-P-8: Observable without watching users

Operators can see whether sync is healthy and can debug a single user's report. Telemetry is about the engine, never about what users wrote. See [11xx: Operations](#11xx-operations).

## Guarantees

Each guarantee is a property a test can check. Written without product terms on purpose: if a guarantee only makes sense for one object type, it belongs to that feature, not the engine. Where a guarantee matches a standard consistency model, its name is given in italics.

### 1xx: Durability

#### SYNC-G-101: Accepted mutations survive the client

Once a mutation has been applied locally, it survives a reload, a crash, closing the app, and an app update, until it is confirmed or rejected. This makes the stored command format a long-lived protocol: deployed clients hold commands written by older versions (`SYNC-G-807`).

#### SYNC-G-102: Each mutation takes effect at most once

Retrying a command, for example after a lost response or a reload mid-request, never applies it twice on the server. A mutation applies entirely or not at all. A retry of a duplicate that is still being processed gets a retryable answer, never a rejection. A retry after the server's idempotency retention window (`OQ-14`) is still applied at most once: it is recognised as a duplicate or rejected, never applied a second time.

#### SYNC-G-103: A mutation is never discarded without being reported

A command leaves the queue only by being confirmed or by being rejected and reported to the user (`SYNC-G-601`). This includes resets (`SYNC-G-801`, `SYNC-G-804`) and sign-out (`SYNC-G-106`).

#### SYNC-G-104: Intermittent connectivity makes progress

On a connection that only lets occasional requests through, every command that reaches the server stays applied and confirmed, even if the connection drops before the rest of the queue is sent. A flush interrupted halfway resumes where it stopped. Overload responses delay the client, honouring any hint from the server about when to retry; they never count as rejections.

#### SYNC-G-105: Storage loss is detected and reported

The client asks the platform for persistent storage where available. It knows when it cannot persist durably (private browsing, quota reached, storage unavailable) and tells the user that offline changes are at risk before they rely on it. A mutation is persisted before it is shown as applied, or the user is warned when leaving the app. If the platform deletes the client's storage, the client detects it on its next start, resets, and reports that unsynced changes from this device may be lost, rather than behaving like a fresh install.

#### SYNC-G-106: Local state and commands belong to one user

Before sign-out or a switch to another user on the same client, pending mutations are sent and confirmed, or the user is told they will be lost and confirms. After sign-out, none of the previous user's local state or stored data can be read. One user's commands are never sent under another user's session, and the server refuses commands from a client that isn't the authenticated user's.

#### SYNC-G-107: A retried command is recognisably the same

Every resend of a command carries the same identity and the same effect, including after the client merges or reorders queued commands. A command that may have reached the server is never merged into a different request or cancelled locally.

#### SYNC-G-108: An expired session pauses the queue

When the server refuses a command because the session is no longer valid, the client keeps the command, stops sending, and asks the user to sign in again. After signing in as the same user, the queue resumes. An authentication failure is never a rejection. If a different user signs in, `SYNC-G-106` applies.

#### SYNC-G-109: Side effects happen at most once

Effects outside the server's state (notifications, messages to people, calls to other systems) happen only if the mutation commits, and at most once, however often the command is retried or runs concurrently.

#### SYNC-G-110: Persistent temporary failures are surfaced

A command that keeps failing with retryable errors is shown to the user after a bounded number of attempts or a bounded time, rather than retried silently forever. It stays queued.

#### SYNC-G-111: Confirmed mutations are never reapplied

Once a mutation is confirmed, it leaves the durable queue and is never replayed, even if confirming it produced no visible change. A reload after confirmation never overwrites newer server state with an older pending value.

#### SYNC-G-112: A backlog of any size is applied in bounded steps

No single request fails because the queue is large. A long-offline client with many queued commands drains them in steps.

#### SYNC-G-113: A queued command is self-contained

Each stored command carries its issuer, client ID, mutation ID, idempotency key and protocol version, independent of the session or connection that eventually sends it. (Keeps relaying and multi-user safety possible; see [Out of scope](#out-of-scope).)

### 2xx: Local responsiveness

#### SYNC-G-201: Reads never wait for the network

When local state exists, every screen renders from it without waiting for any network request. Local reads have a latency budget of their own: on devices where local storage is slower than expected, rendering is still not blocked on it.

#### SYNC-G-202: Mutations apply locally without waiting

A mutation is visible in local state before any network request for it completes, online or offline.

#### SYNC-G-203: Clients create objects with their own IDs

A client can create an object and then refer to it (edit it, create children) without a server round trip. IDs created by different clients never collide.

#### SYNC-G-204: Initial sync is usable before it is complete

A client without local state (first sign-in, new device, after a reset) becomes usable for what the user is looking at before the rest of the data has arrived. Data is fetched in priority order (`OQ-11`); eventually the client holds everything it may see, as before. Prioritization never delays deletions or the undoing of rejected mutations.

#### SYNC-G-205: Incomplete data is never shown as complete

While data a screen depends on hasn't arrived, the screen can tell, and shows it as loading rather than as empty or missing. "No expenses" and "expenses not loaded yet" are different states.

#### SYNC-G-206: Completeness is tracked per scope

Whether data has fully arrived is known per collection or sync scope, not as one "synced" flag for the whole client. Computations over a collection (totals, counts) can ask whether the collection is complete. (Needed for `SYNC-G-205`; keeps partial availability possible.)

### 3xx: Convergence and consistency

#### SYNC-G-301: Clients converge when quiescent

When all clients are connected and the system is quiescent, every client's local state equals the server state visible to it, within the bound from `OQ-6`. *(Convergence.)*

#### SYNC-G-302: Catch-up sync misses nothing

After catch-up sync, a client has every change committed on the server since its last sync, including changes from transactions that were in flight while the previous sync ran, and changes committed while the catch-up request itself was in flight. (See `OQ-1` for the Postgres cursor hazard.)

#### SYNC-G-303: Deletions propagate and stay

An object deleted on the server disappears from every client, whether the client was connected at the time or catches up later. This includes objects removed as a consequence of deleting another object. A deleted object is never brought back by a delayed, retried or stale mutation, and a client behind the server's deletion retention window is reset rather than left holding deleted objects.

#### SYNC-G-304: Live updates and catch-up sync agree

For the same set of server changes, a client that received them live and a client that received them via catch-up sync end up with the same local state. Live updates are applied in server commit order. *(Path independence.)*

#### SYNC-G-305: Reload changes nothing

Reloading a client that has converged shows exactly the same local state as before the reload.

#### SYNC-G-306: Local state is referentially complete

The client never presents an object whose required parent or referenced object is missing from local state, whatever order data arrives in. Relationships are declared at registration (`SYNC-P-6`), and prioritized fetching (`SYNC-G-204`) fetches what an object depends on before or together with the object.

#### SYNC-G-307: Server transactions apply atomically

Changes the server committed together reach the client together and are applied in one step, also when catch-up arrives in pages. The client never shows a state where part of a server transaction is applied and part isn't (for example an object updated without its children). *(Atomic visibility.)*

#### SYNC-G-308: Server state never moves backwards

Once a client has shown server state that includes a change, it never again shows server state from before that change, whatever order live updates, catch-up responses, prioritized fetches and reloads arrive in. Live updates arriving during catch-up are neither lost nor overwritten by older catch-up data. Decided without comparing clocks. *(Monotonic reads.)*

#### SYNC-G-309: A cursor the server can't serve leads to a reset

If the client's cursor is unknown to the server, ahead of it, or older than the server's retained history, the server answers with an explicit reset, never with an incomplete delta. Pending work is kept (`SYNC-G-801`).

#### SYNC-G-310: Every server change propagates, whatever made it

A change to synced data reaches every client that may see it, by live update and by catch-up sync, under the same guarantees as changes from mutations. That includes background jobs, admin tools, data migrations and server-side cascades.

#### SYNC-G-311: Local server state is a consistent prefix

The server state a client holds always equals the server's state at a single point in its commit order, across all objects. It never includes a change without every change committed before it in the same scope. *(Consistent prefix; gives causal visibility: no reply without the change it replies to.)*

#### SYNC-G-312: Redelivery is harmless and gaps are detected

Receiving a server change the client already has, or one older than its current state, leaves local state unchanged. A gap in live updates is detected and closed through catch-up sync.

#### SYNC-G-313: Divergence is detected and repaired

The client can verify that its local server state matches the server's, per scope. A mismatch is detected without user action and triggers a reset of the affected data under `SYNC-G-801` rules.

#### SYNC-G-314: Others' changes are never withheld

While connected, changes by other users reach local state within the `OQ-6` bound, even if this client has pending, stuck or failing mutations. One client's large catch-up never delays live updates to other clients beyond that bound.

#### SYNC-G-315: Full sync and catch-up agree

From the same server state, a client that resets and loads everything ends up with exactly the same local state as a client that catches up incrementally from any earlier cursor, pending mutations included.

#### SYNC-G-316: The cursor never runs ahead of local data

The client records a new cursor only after everything up to it is persisted locally. A crash at any point leads, after restart, to the same state as an uninterrupted sync.

#### SYNC-G-317: A change the client can't apply doesn't stop it

If the client can't apply a server change (unknown type or field, apply error), it keeps applying unrelated changes and keeps its pending mutations, records the failure for diagnostics (`SYNC-G-806`, `SYNC-G-1102`), and reports its state as possibly out of date (`SYNC-G-1005`). It never needs its storage cleared to recover.

#### SYNC-G-318: The cursor is opaque

The client stores the cursor and sends it back unchanged. It never parses it, compares it with a clock, or derives anything from it. (Keeps `SYNC-P-7`; keeps per-scope and regional cursors possible.)

### 4xx: Ordering and confirmation

#### SYNC-G-401: A client's mutations apply in the order it issued them

The server applies one client's commands in the order the client issued them. Ordering *across* clients is the server's choice. Re-issuing a rejected mutation creates a new mutation, ordered after the existing ones. *(Monotonic writes.)*

#### SYNC-G-402: Own pending changes never flicker back

A client never shows a server state that doesn't yet include its own pending mutations. No flicker back to an older value while a change is in flight. The guarantee is per client; across a user's devices see `SYNC-G-902`. *(Read your writes.)*

#### SYNC-G-403: Pending state ends only on confirmation

A mutation stops being shown as pending only once the client has received server state that includes it, or once it is rejected. That includes writes the server applies asynchronously after responding. Determined without comparing clocks (`OQ-2`).

#### SYNC-G-404: Local state is server state plus pending mutations

At any moment, local state equals the latest server state the client received, including server-side effects of earlier mutations, with its pending mutations applied in order. A mutation's effect is recomputed against new server state, not kept as a stale snapshot (`OQ-3`). Mutations target objects by ID, never by position.

#### SYNC-G-405: Recomputing pending mutations has no side effects

Re-applying pending mutations to new server state is deterministic: it produces the same IDs and client-generated values as the first time, and never repeats anything user-visible (notifications, messages, outcome reports). If re-application fails locally, the mutation is not rejected: it stays pending until the server decides. The server's copy of a client's own mutation is never presented as someone else's change (`SYNC-G-1004`).

#### SYNC-G-406: Server-assigned values are provisional while pending

A field whose value the server assigns (a timestamp, a sequence number, a computed field) is shown as provisional until confirmation. It may hold a placeholder or a local estimate, but it is never presented as final, and its replacement on confirmation doesn't count as someone else's change.

#### SYNC-G-407: A missing confirmation is detected

If the server has acknowledged a mutation but no server state including it arrives within the `OQ-6` bound, the client fetches it through catch-up sync. A mutation is never left pending indefinitely, and never treated as confirmed on the strength of the response alone.

#### SYNC-G-408: A mutation records intent and base values

A mutation is stored as a named intent with arguments ("add member", "rename"), together with the values of the fields it touches as the user saw them. Not as the resulting state alone. (Needed for replay under `OQ-3`, for overwrite detection under `SYNC-G-504`, and keeps undo possible.)

### 5xx: Concurrent changes

#### SYNC-G-501: Each field has a declared merge rule

Every field of every synced type has a merge rule from a small, fixed set, declared at registration (`OQ-5`). A rule may cover a declared group of fields that must change together (for example a parent and a position). The engine applies the rule; it doesn't guess.

#### SYNC-G-502: Concurrent edits to different fields both survive

Two clients changing different fields of the same object, concurrently or offline, both see both changes after convergence.

#### SYNC-G-503: Concurrent additions to a collection both survive

Two clients adding members to the same collection concurrently both see both additions after convergence.

#### SYNC-G-504: Overwrites are detectable and reversible

When a user's change is overwritten by a concurrent change, the client can tell that it happened and what the user's value was (`OQ-10`), and the user can restore it by issuing it as a new mutation. Detection doesn't depend on the client having seen every intermediate state.

#### SYNC-G-505: Mutations are validated against current server state

The server validates each mutation against server state at the moment it applies it, not against the state the issuing client saw. A mutation that a concurrent change has made invalid is rejected (`SYNC-G-601`), not applied. A mutation issued after the client saw a change is ordered after that change. The server never authorizes reads against unconfirmed state. *(Writes follow reads.)*

#### SYNC-G-506: Invariants hold under concurrency

Rules that span several objects (a limit, a uniqueness, "at most one") hold after any interleaving of concurrent mutations from any number of clients. Two mutations that are each valid alone but invalid together never both apply. *(No write skew.)*

#### SYNC-G-507: An object is always in exactly one place

Moving an object to a new parent or position is a single mutation, never a delete plus a create. In every local state, before and after convergence, the object appears in exactly one location. Concurrent moves of the same object resolve to one location. A move that would make an object its own ancestor is rejected.

#### SYNC-G-508: Contested outcomes are shown as provisional

When a pending mutation's success depends on a rule that spans several objects (`SYNC-G-506`), the client exposes it as contested until confirmed, distinct from plain pending. The user is never told they got something the server hasn't granted.

#### SYNC-G-509: Concurrent insertions don't interleave

When two clients each insert a run of consecutive members at the same position in an ordered collection, each run stays contiguous and in its original order after convergence. (Applies once ordered collections exist, `OQ-5`.)

#### SYNC-G-510: Merge rules are an open, named set

Merge rules are referred to by name at registration. Adding a rule is a protocol change: a client that doesn't know a rule is handled by the protocol gate (`SYNC-G-802`), never by guessing. (Keeps a per-field text CRDT possible.)

### 6xx: Rejection

#### SYNC-G-601: Rejections are visible and explained

When the server rejects a mutation, the client promptly undoes its local effect, without waiting for unrelated commands to drain, and tells the user which change failed and why. The report survives a reload until the user has acknowledged it (`OQ-9`). Other clients never see the effects of a rejected mutation.

#### SYNC-G-602: Mutations that depend on a rejected one are handled by a defined rule

When a rejected mutation has later mutations that depend on it (editing an object whose creation was rejected), those follow a single, documented policy (`OQ-4`). They are never applied to the wrong state silently.

#### SYNC-G-603: A rejection never blocks the queue forever

A permanently rejected command does not prevent later independent commands from being applied. A command is never held at the head of the queue deliberately.

#### SYNC-G-604: Rejections caused by someone else say so

When a mutation is rejected because of a concurrent change by another user (`SYNC-G-505`), the report says so, and names the change and its author when the user may see them. "Someone already took the last spot" rather than "invalid".

### 7xx: Access and visibility

Visibility is per object: a field that some recipients may not see must be its own object.

#### SYNC-G-701: Clients only hold what the user may see

When a user loses access to objects, every client of that user removes them from local state and local storage, whether connected at the time or on next contact with the server, within the `OQ-6` bound. When a removal has completed is observable.

#### SYNC-G-702: Permissions in local state are current

Permission information shown or used by the client reflects the current server policy after convergence, including after a policy change that didn't touch the objects themselves. A policy change reaches clients without a manual cache version bump.

#### SYNC-G-703: Commands for objects the user lost access to are settled

Queued commands for objects the user can no longer access are rejected and reported per `SYNC-G-601`, not retried forever.

#### SYNC-G-704: Gaining access delivers existing objects

When a user gains access to objects, every client of that user receives all of them, including objects created before access was granted and objects nobody has changed since, whether connected at the time or catching up later.

#### SYNC-G-705: Visibility is recomputed, not inferred from changes

Catch-up sync and live updates add or remove objects whose visibility changed for the user, even when the objects themselves did not change. An object stays as long as the user can reach it by any route, and is removed when no route remains.

#### SYNC-G-706: Online-only actions are declared

Actions that need a connection (for example signing in or sending an invite) are declared at registration. The client can query whether an action is online-only, so the user is told before starting it, not with a failure afterwards.

### 8xx: Reset and versioning

#### SYNC-G-801: A reset preserves unsynced work

When a client must reset (see Reset in [Terminology](#terminology)), its pending mutations are either replayed against the fresh state or reported as not applied. Never dropped silently. An interrupted reset resumes, and never shows partial state as complete.

#### SYNC-G-802: Old clients either work or are told to update

A client on an older version either syncs correctly or is told it must update, before it sends anything the server would misinterpret. Its pending mutations are kept until it has updated. Clients ignore message kinds, object types and fields they don't know, without error. (See `doc/protocol-versioning.md`.)

#### SYNC-G-803: There is no maximum offline duration that loses data

A client offline for any length of time can reconnect without losing pending work. Longer absences may cost a reset, not data.

#### SYNC-G-804: The user can always repair their client

The user can trigger a reset themselves at any time, without developer tools: local server state is discarded and rebuilt from the server. Their unsynced work is handled as in `SYNC-G-801`, and before anything is discarded they are told what will happen to it (`OQ-13`). An escape hatch for states nobody anticipated, and for peace of mind.

#### SYNC-G-805: The server can make clients reset

The server can instruct clients (all, or a selection such as one user's or one version's) to reset on their next sync, for example after fixing a bug that left bad data on clients. The same rules as `SYNC-G-801` apply.

#### SYNC-G-806: Client sync state can be inspected

A client can produce a diagnostic snapshot of its sync state (cursor, queue, pending and failed mutations, connection history, versions, counts of corrections, overwrites and rejections) that a user can send along with a bug report (`SYNC-G-1105`). It contains no more of the user's data than needed, and can be loaded into a test harness to reproduce the state.

#### SYNC-G-807: Queued commands survive version changes

A queued command written by any supported older version, of the app or of the local cache, is applied or reported after the update. Never silently dropped or ignored.

#### SYNC-G-808: A reset doesn't change outcomes

Pending mutations replayed after a reset reach the same server state, and the same rejections, as they would have through normal sync. A reset changes how long reconciliation takes, never its result.

### 9xx: Multiple clients per user

#### SYNC-G-901: Multiple tabs don't conflict

Several clients of the same user in the same browser share storage without duplicating, losing or double-applying commands (`OQ-7`). This holds on platforms without cross-tab coordination APIs, and every tab's mutations are durable, not only the leading tab's.

#### SYNC-G-902: A user's other devices are just other clients

A user's changes reach their other devices the same way they reach other users. No device has special status.

### 10xx: Transparency

The guarantees behind [Never surprised](#never-surprised). They are about what state the engine *exposes*; how the UI presents it is product design.

#### SYNC-G-1001: Sync state is queryable per object

For any object, the client can ask: does it have pending mutations, did a mutation on it fail, and has it been changed by someone else since the user last looked (`OQ-8`). The client is notified when any of these change, even if the object's data didn't.

#### SYNC-G-1002: Connection state reflects measured reachability

Connection state is based on actual contact with the server, not on what the device reports (`navigator.onLine` says nothing about whether anything gets through). Besides connected and offline, it distinguishes *degraded*: technically connected, but messages are slow or mostly not getting through (`OQ-12`). The client always knows when it last heard from the server. When reachability returns, or the user asks to retry, the client tries to reconnect immediately rather than waiting out its backoff.

#### SYNC-G-1003: Unsynced work is always listable

At any moment the client can list every pending and failed mutation, in a form the user can understand. Descriptions and rejection reasons persist across reloads like the commands themselves.

#### SYNC-G-1004: Others' changes are attributable

When a live update or catch-up sync changes an object the user can see, the client knows who made the change. Changes arriving in bulk (a long catch-up, a reset) can be summarised as a batch rather than one cue per object.

#### SYNC-G-1005: Freshness is known

The client can tell whether the local state it shows might be out of date (offline or not yet caught up), distinct from whether it has pending changes, per screen or data set as well as for the whole client. (Prior art: Firestore's `fromCache` vs `hasPendingWrites`.)

#### SYNC-G-1006: A stalled connection is detected, not waited on

A connection that has stopped delivering messages without closing is detected within a bounded time (`OQ-12`) and treated as degraded or offline. No request, sync or flush waits indefinitely on it.

#### SYNC-G-1007: Work in flight shows progress

When mutations are being sent or catch-up sync is running, the client can show that it is happening and how far along it is, so a slow connection looks slow rather than stuck.

#### SYNC-G-1008: Mutation outcome is observable

For any mutation it issued, the client can ask its state and be notified when it changes: *queued* (not sent yet), *sent* (sent, outcome unknown), *confirmed* or *rejected*. A mutation that touches several objects (an object and its children) has one state for the whole. Confirmed means the same as in `SYNC-G-403`: the client has server state that includes it, not just a successful response.

#### SYNC-G-1009: "Everything is saved" is observable

The client exposes one signal for "nothing is pending and everything I may see has been downloaded", so the user can put the phone away or go offline with confidence. It can also wait until it has caught up with the server as of a given moment, for example before acting on a deep link.

#### SYNC-G-1010: Connection state doesn't flap

The client marks a connection degraded as soon as measured quality crosses the threshold. It returns to connected only after quality has stayed good for a hold period, and repeated degradations within a window lengthen that period, up to a stated maximum (`OQ-12`).

#### SYNC-G-1011: Progress has a fixed denominator

Progress reported under `SYNC-G-1007` is measured against the work outstanding when the operation started. It only moves forward and reaches complete exactly when that work is done. Work that arrives later starts a new measurement.

#### SYNC-G-1012: Sync responses are never served from a cache

No HTTP or service-worker cache ever answers a catch-up, sync or confirmation request.

### 11xx: Operations

Guarantees for operators, under `SYNC-P-8`.

#### SYNC-G-1101: Sync health is measured

The server records aggregate metrics, per protocol and app version: queue lengths and the age of the oldest pending mutation, rejection rates by type and reason, resets by cause, catch-up size and duration, reconnect rates, and convergence lag (time from a server commit to it being applied on clients). The lag metric makes the `OQ-6` bound observable in production.

#### SYNC-G-1102: Clients report sync errors

Rejections, server changes the client couldn't apply, storage failures and unhandled sync errors reach the server. Reports are batched, queued while offline, rate-limited, and free of user content (`SYNC-G-1107`).

#### SYNC-G-1103: Stuck and diverged clients are visible

Operators can see clients whose queue doesn't drain while connected, and clients whose state doesn't match the server's (`SYNC-G-313`), without waiting for a user to complain.

#### SYNC-G-1104: A mutation can be traced end to end

A mutation's ID and idempotency key appear in the client's diagnostics, the server's request log, the stored change and the broadcast. An operator can follow one mutation from the device that issued it to every device that received it, or find where it stopped.

#### SYNC-G-1105: A user report links to diagnostics, with consent

A user can attach the diagnostic snapshot (`SYNC-G-806`) to a report, per report, after seeing what it includes. Nothing is sent without that consent.

#### SYNC-G-1106: The server's view of a client is inspectable

Operators can see, per client: its cursor, last contact, protocol and app version, outstanding acknowledgements and recent rejections. Together with `SYNC-G-805` this covers looking and fixing.

#### SYNC-G-1107: Telemetry never contains user content

Telemetry and error reports contain IDs, types, counts, timings and error codes, never field values, names or free text. Every payload conforms to an allowlist schema. Aggregates avoid user identifiers where possible; anything identifying is kept only for a short, documented period.

#### SYNC-G-1108: Reconnecting clients don't arrive together

When many clients lose their connection at the same moment (a deploy, a server restart), their reconnects, catch-up syncs and queue flushes are spread over time by randomised, capped backoff. Mass resets complete without loops, and recovery doesn't overload the server.

## Never surprised

What the user should be able to see, independent of screen design. Every row must be supported by the guarantees above. Corrections (an overwrite, a rejection, a reset) are shown quickly and clearly, never hidden behind a long animation.

| Situation | The user can see | Backed by |
|---|---|---|
| I made a change, online | It applied immediately; briefly marked as unconfirmed if the server is slow | `SYNC-G-202`, `SYNC-G-1001`, `SYNC-G-1008` |
| I made a change, offline | It applied; it is marked as not yet shared with others | `SYNC-G-202`, `SYNC-G-1001`, `SYNC-G-1003` |
| I claimed something limited (the last spot) | That it isn't certain until the server confirms | `SYNC-G-508` |
| I want to put the phone away or go offline | That everything is saved and downloaded, or exactly what isn't | `SYNC-G-1003`, `SYNC-G-1009` |
| I'm offline | That I'm offline, since when, and that what I see may be out of date | `SYNC-G-1002`, `SYNC-G-1005` |
| My connection is poor but not gone | That the connection is poor, when the server was last reached, and that my changes are still being sent | `SYNC-G-1002`, `SYNC-G-1006`, `SYNC-G-1007` |
| I try something that needs a connection, while offline | That it needs a connection, before I start | `SYNC-G-706` |
| My device can't store changes safely | That offline changes are at risk (private browsing, storage full) | `SYNC-G-105` |
| I open the app on a new device | What I'm looking at first, with anything still loading marked as loading, not as empty | `SYNC-G-204`, `SYNC-G-205` |
| I reconnect | My changes being sent; then confirmation, or which ones failed and why | `SYNC-G-403`, `SYNC-G-601` |
| Someone else changes what I'm looking at | That it changed, and who changed it | `SYNC-G-1004` |
| My offline change was overwritten | That it was overwritten, by whom, what my value was, and a way to restore it | `SYNC-G-504`, `SYNC-G-1004` |
| My change was rejected | Which change, why, and what happened to changes that built on it, until I've seen it | `SYNC-G-601`, `SYNC-G-602` |
| My change was rejected because of someone else | That another user's change caused it, and which one | `SYNC-G-604` |
| A change keeps failing to send | That it's stuck, and that it is still kept | `SYNC-G-110` |
| My session expired | That I need to sign in again, and that my changes are kept meanwhile | `SYNC-G-108` |
| I sign out with unsynced changes | That they haven't been sent, before anything is discarded | `SYNC-G-106` |
| Something seems wrong | A way to repair the app myself, and what happens to my unsynced changes if I do | `SYNC-G-804` |
| I lost access to something | That it's gone and why, not that it just vanished | `SYNC-G-701`, `SYNC-G-703` |
| I was given access to something | All of it, not just what changed recently | `SYNC-G-704` |
| The app needs to update | That it must update, and that my unsynced changes are safe | `SYNC-G-802`, `SYNC-G-807` |

## Scenarios

Product situations, each pointing at the guarantees it relies on. The scenarios are where Tayaway's domain appears; the guarantees stay domain-free.

#### SYNC-S-001: Shopping without signal

A user opens a shopping list in a supermarket without signal, ticks off items, adds two, and leaves. Meanwhile another member adds an item at home. When the first user's phone reconnects, both see the full, combined list.

Relies on: `SYNC-G-101`, `SYNC-G-201`, `SYNC-G-202`, `SYNC-G-301`, `SYNC-G-503`, `SYNC-G-1001`.

#### SYNC-S-002: Two people edit the same event offline

Two members both edit an event while offline: one changes the title, the other the date and the title. After both reconnect, both see the same result, and the user whose title lost can see that it was overwritten.

Relies on: `SYNC-G-301`, `SYNC-G-501`, `SYNC-G-502`, `SYNC-G-504`, `SYNC-G-1004`.

#### SYNC-S-003: Create, edit, delete while offline

Offline, a user creates an item, renames it, adds a sub-item, then deletes the item. On reconnect, the server and every client end up as if nothing happened, with no errors shown.

Relies on: `SYNC-G-203`, `SYNC-G-401`, `SYNC-G-303`, `SYNC-G-102`.

#### SYNC-S-004: Parent deleted while I edit a child

A user edits an item on a list while offline. Meanwhile, another member deletes the whole list. On reconnect the list is gone for both, and the first user is told their edit could not be applied, and why.

Relies on: `SYNC-G-303`, `SYNC-G-601`, `SYNC-G-602`.

#### SYNC-S-005: Removed while offline

A member is removed from a workspace while their phone is offline with queued changes. On reconnect, the workspace's data disappears from their device, and they are told their queued changes were not applied.

Relies on: `SYNC-G-701`, `SYNC-G-703`, `SYNC-G-103`.

#### SYNC-S-006: Response lost mid-request

A user saves a change on a train; the request reaches the server but the response is lost when the train enters a tunnel. The client retries later. The change is applied once.

Relies on: `SYNC-G-102`, `SYNC-G-403`.

#### SYNC-S-007: Back after a long trip

A user opens the app after three weeks without using it, with a few changes queued from the day they left. The app shows their old data immediately, then catches up, and their queued changes are either applied or reported.

Relies on: `SYNC-G-201`, `SYNC-G-309`, `SYNC-G-801`, `SYNC-G-803`, `SYNC-G-1005`.

#### SYNC-S-008: App update with changes queued

A new version is deployed while a user has queued offline changes, possibly with a new cache or schema version. When they come online, their changes are not lost, whether the old version can still sync or must update first.

Relies on: `SYNC-G-101`, `SYNC-G-802`, `SYNC-G-807`.

#### SYNC-S-009: Validation fails on a change made offline

A user makes a change offline that is valid locally but rejected by the server on reconnect (for example a rule changed in the meantime). The change is undone and the user is told which change and why.

Relies on: `SYNC-G-601`, `SYNC-G-603`, `SYNC-G-1003`.

#### SYNC-S-010: Two tabs open

A user has the app open in two tabs and makes changes in both while offline. On reconnect each change is applied exactly once, and both tabs show the same result.

Relies on: `SYNC-G-901`, `SYNC-G-102`, `SYNC-G-305`.

#### SYNC-S-011: Phone clock is wrong

A user's phone clock is an hour behind. Their changes sync and are ordered correctly, and pending markers clear as normal.

Relies on: `SYNC-P-7`, `SYNC-G-318`, `SYNC-G-403`, `SYNC-G-301`.

#### SYNC-S-012: Busy event, many live changes

Twenty members are editing the same event at once. Every connected client converges, and no change is missed even when several commit in the same instant.

Relies on: `SYNC-G-301`, `SYNC-G-302`, `SYNC-G-304`, `SYNC-G-311`.

#### SYNC-S-013: Reload mid-sync

A user reloads the page while commands are being sent and catch-up sync is in progress. Nothing is lost or duplicated, and the reloaded app shows the same state it was converging to.

Relies on: `SYNC-G-101`, `SYNC-G-102`, `SYNC-G-305`, `SYNC-G-316`.

#### SYNC-S-014: Last spot taken

Two members, both offline, each sign up for the last free slot of something that has a limit. Until they reconnect, each sees the signup as not yet certain. When they reconnect, exactly one of them has the slot. The other's change is undone, and they are told someone else got there first.

Relies on: `SYNC-G-505`, `SYNC-G-506`, `SYNC-G-508`, `SYNC-G-601`, `SYNC-G-604`.

#### SYNC-S-015: One bar of signal

A user's phone reports a connection, but only the occasional request gets through. The app says the connection is poor, keeps working from local state, and sends queued changes as the connection allows; each change that gets through stays confirmed. The user never stares at a spinner that won't finish.

Relies on: `SYNC-G-104`, `SYNC-G-201`, `SYNC-G-1002`, `SYNC-G-1006`, `SYNC-G-1007`, `SYNC-G-1010`.

#### SYNC-S-016: First open on a new device

A member of a large workspace signs in on a new phone, from a link to one event. That event and what it needs show up first and are usable; the rest of the workspace follows in the background. Lists that haven't loaded yet say so instead of looking empty.

Relies on: `SYNC-G-204`, `SYNC-G-205`, `SYNC-G-206`, `SYNC-G-306`.

#### SYNC-S-017: Deep link to dependent data

A user opens a link straight to an expense on a client that doesn't have the expense's event yet. The expense is shown only once what it depends on is there, never with a missing event.

Relies on: `SYNC-G-205`, `SYNC-G-306`, `SYNC-G-307`, `SYNC-G-1009`.

#### SYNC-S-018: The app looks wrong

A user sees something that doesn't match what another member sees and suspects the app. They use the repair option: they are told their unsynced changes are safe (or what happens to them), the app rebuilds its state from the server, and both users now see the same thing. If they report the problem, the report includes a diagnostic snapshot, with their consent.

Relies on: `SYNC-G-804`, `SYNC-G-801`, `SYNC-G-806`, `SYNC-G-1105`.

#### SYNC-S-019: Added to an event with history

A member is added to an event that already has lists and expenses nobody has touched in weeks. All of it appears on their devices, including a device that was offline when they were added.

Relies on: `SYNC-G-704`, `SYNC-G-705`, `SYNC-G-302`, `SYNC-G-205`.

#### SYNC-S-020: Lost response, then more edits

A user creates an item on a flaky connection; the request reaches the server but the response is lost. Still offline, they rename the item, then delete it. On reconnect, the item is gone on the server and on every client, and it never reappears.

Relies on: `SYNC-G-102`, `SYNC-G-107`, `SYNC-G-303`.

#### SYNC-S-021: Handing over the phone

A user with queued offline changes signs out so a partner can sign in on the same phone. They are warned about the unsent changes first. Their changes are never applied under the partner's account, and the partner sees none of their data.

Relies on: `SYNC-G-106`, `SYNC-G-103`.

#### SYNC-S-022: Session expires with changes queued

A user's session expires while they have queued changes. The app asks them to sign in again and keeps the changes meanwhile; after signing in they are sent.

Relies on: `SYNC-G-108`, `SYNC-G-101`.

#### SYNC-S-023: Storage evicted

The browser clears the app's storage after weeks without use. On the next open, the app notices its local state is gone, rebuilds from the server, and tells the user that changes made on this device that hadn't synced may be lost, instead of acting as if it were a new install.

Relies on: `SYNC-G-105`, `SYNC-G-801`.

#### SYNC-S-024: Server restored from backup

The server is restored from a backup taken an hour earlier. Clients whose cursor is now ahead of the server notice, reset, and replay or report their pending changes, instead of keeping objects the server no longer has.

Relies on: `SYNC-G-309`, `SYNC-G-801`, `SYNC-G-808`.

#### SYNC-S-025: Live update arrives during catch-up

A client reconnects and starts catching up. While catch-up runs, another member makes a change that arrives as a live update. After catch-up, the client shows the live change, not an older version from the catch-up data.

Relies on: `SYNC-G-308`, `SYNC-G-304`, `SYNC-G-302`.

#### SYNC-S-026: Offline delete rejected

A user deletes an item offline that they turn out not to be allowed to delete. On reconnect the item comes back, with an explanation.

Relies on: `SYNC-G-601`, `SYNC-G-1003`.

#### SYNC-S-027: Ready for a flight

Before boarding, a user checks whether the app has everything it needs. The app shows that all their changes are sent and all their data is downloaded, or what is still missing.

Relies on: `SYNC-G-1009`, `SYNC-G-206`, `SYNC-G-1003`.

#### SYNC-S-028: My own change hides something from me

A user makes a valid change that removes their own access to an object (for example leaving an event). The object disappears, and the user can tell that it disappeared because of their own change (`OQ-15`).

Relies on: `SYNC-G-701`, `SYNC-G-705`, `SYNC-P-4`.

## Out of scope

Deliberate non-goals. Revisit only by changing this list. Checked for reversibility on 2026-11-28.

### Ruled out by principle

One-way doors already taken, deliberately. Adding any of these would mean revisiting a principle.

- **Peer-to-peer sync.** Clients sync only through the server. Ruled out by `SYNC-P-2` and `SYNC-P-7` (ordering without a server needs client clocks), and `SYNC-G-506` (invariants need one coordinator). A limited variant, one device relaying another's queued commands to the server, stays possible thanks to `SYNC-G-113`.
- **End-to-end encryption.** The server reads all data to authorize, validate and order. Ruled out by `SYNC-P-2` and `SYNC-G-505`. Encrypting individual free-text fields that the server never interprets would be a separate, much smaller feature.
- **Multi-master servers.** There is one authoritative database. Ruled out by `SYNC-P-7` and `SYNC-G-506`.
- **Using the data without the server.** Ruled out by `SYNC-P-2`, `SYNC-G-701` (data is removed when access is lost) and `SYNC-G-804` (local state can be discarded).
- **Finality of local writes.** An offline change is never guaranteed to succeed; the server decides (`SYNC-P-2`).

### Deferred, reversible

Not needed now, and kept possible by the guarantee in brackets.

- **Character-level collaborative text editing.** Concurrent edits to a text field merge by the field's rule (`OQ-5`), not character by character. If a rich-text field ever needs it, that field gets a dedicated CRDT merge rule, outside the engine core (as Linear and Notion did). (`SYNC-G-510`, `SYNC-G-408`)
- **Partial offline availability.** A client eventually holds everything it may see in the current workspace. Choosing what to keep offline (Notion-style) is not needed at Tayaway's scale. Prioritizing *what arrives first* (`SYNC-G-204`) is in scope; it changes the order, not the end result. (`SYNC-G-206`, `SYNC-G-318`)
- **First use offline.** Signing in, accepting an invite, or opening a workspace for the first time on a device needs a connection. Creating a new workspace offline is not ruled out. (`SYNC-G-203`, `SYNC-G-706`)
- **Data export.** Exporting a user's data in a standard format. (Objects are already self-describing.)
- **Undo history.** The engine doesn't provide undo/redo. A feature can build it from mutations, because each mutation records the values it replaced; an undo is then a new mutation, validated like any other. (`SYNC-G-408`)
- **Regional homing.** Placing each workspace in one region, with one writer per workspace. (`SYNC-G-318`)

### Not the engine's job

- **Losing access is not retroactive.** What a user has seen, they may have kept; removal stops future reads, not past ones.
- **Branches, private drafts, suggest-and-review.** Every mutation is shared once synced.
- **Presence and ephemeral state.** Who is viewing, typing indicators and similar transient state.
- **Unsubmitted input.** Text typed but not yet turned into a mutation is the app's responsibility.

## Open questions

Decisions the spec needs before the guarantees above can be final. Each lists the options seen in prior art.

- **OQ-1: Catch-up cursor.** `SYNC-P-7` rules out the current wall-clock timestamp, and `SYNC-G-318` makes it opaque. In Postgres, `updated_at`/`now()` is unsound (it is the transaction's start time, but rows become visible at commit), and a plain sequence is unsound on its own (assigned before commit, so lower values can appear later). Sound options:
  - a gapless counter assigned under a lock (serialises writes; Linear-like);
  - an `xid8` column read only below the snapshot horizon (`pg_snapshot_xmin`), with `(xid, id)` as cursor (delivery stalls behind long or idle transactions);
  - the logical replication position (commit-ordered; operationally heavier; PowerSync, Figma LiveGraph);
  - a client-view-record diff (Replicache row-version; also handles deletions and visibility changes, `SYNC-G-705`).

  NOTIFY delivers in commit order, so the live path should carry the cursor in each message. Also to decide: compaction instead of tombstone expiry (PowerSync), and how the cursor is scoped (per workspace, per client group). Sync IDs may have gaps that are not missing data (Linear). Affects `SYNC-G-302`, `SYNC-G-307`, `SYNC-G-309`, `SYNC-G-311`.
- **OQ-2: How a client knows its mutation is confirmed.** `SYNC-P-7` rules out timestamp comparison. Options: the server returns the cursor position that includes the mutation, confirmed when the client's cursor reaches it (Linear); per-client mutation ID acknowledged by the server (Replicache `lastMutationID`, game netcode); the write's transaction ID, confirmed with `pg_visible_in_snapshot` (TanStack DB `awaitTxId`; must be read inside the write's own transaction); write checkpoints (PowerSync). Likely decided together with `OQ-1`. Affects `SYNC-G-402`, `SYNC-G-403`, `SYNC-G-407`.
- **OQ-3: Overlay or replay.** Keep pending changes as diffs merged over server state (current; Linear rebases the original value) vs re-run pending mutations against each new server state (Replicache, game netcode; requires mutations recorded as intent, `SYNC-G-408`) vs hold server state back until pending writes are confirmed (PowerSync; costs `SYNC-G-314`, since a stuck queue withholds everyone else's changes) vs discard incoming values that conflict with pending ones (Figma). Affects `SYNC-G-404`, `SYNC-G-405`.
- **OQ-4: What happens to mutations after a rejected one.** Skip and continue (current; PowerSync and Replicache for permanent errors) vs lose later edits to the same object only (Realm) vs reject dependants too (Jazz; needs knowing what depends on what) vs flag dependants for review (Electric's guide). Wiping all local state is the documented anti-pattern. Affects `SYNC-G-602`, `SYNC-G-603`.
- **OQ-5: The set of merge rules.** Candidates: last-writer-wins per field, server-ordered (Figma); add-wins set for collections; counter; append-only collection; fractional index for ordering, with the server fixing collisions (Figma); "reject if the base version is stale" as a precondition rule. Also to decide: delete versus concurrent update (most engines: delete wins; Tayaway reports, `SYNC-S-004`); re-creating a deleted ID; how embedded or JSON-valued fields merge (whole value or per key); derived writes. Ink & Switch found the default rules sufficient, which supports a small fixed set. Affects `SYNC-G-501`–`SYNC-G-503`, `SYNC-G-509`, `SYNC-G-510`.
- **OQ-6: Convergence bound.** What "within bounded time" means in numbers, for live updates, for catch-up after reconnect, and for reconnect with a large queue (rebasing many pending mutations can be slow). Needed to make `SYNC-G-301` testable; measured in production by `SYNC-G-1101`.
- **OQ-7: Multiple tabs.** One shared queue with a leader tab elected via Web Locks (LiveStore, TanStack DB, Notion, PowerSync), or per-tab queues with cross-tab coordination. Constraints: Android Chrome has no SharedWorker; iOS Safari is limited; service workers are unsuitable as leader because they stop when idle; leader handover when a tab crashes. Notion corrupted its local database with multiple writers. Affects `SYNC-G-901`.
- **OQ-8: "Changed since I last looked".** Does the engine track what the user has seen (as Apple Notes' "updates since you last viewed" does), or only expose who changed what and when and leave "seen" to the UI? Affects `SYNC-G-1001`.
- **OQ-9: Rejection reporting.** How a failed mutation stays visible until acknowledged (for example in a list of unsynced changes), and how its payload stays recoverable so the user can redo it. A Rocicorp engineer: "offline mutations should never be rejected", or users lose arbitrarily large amounts of work. Affects `SYNC-G-601`, `SYNC-G-1003`.
- **OQ-10: How much of an overwritten value to keep.** Only the fact that an overwrite happened, the user's value until acknowledged (Automerge's conflicts object), a synced conflicts table (PowerSync), or a revert point around a large replay (Figma autosave). Last-writer-wins is only tolerable when the lost value can be recovered (Google Drive). Affects `SYNC-G-504`.
- **OQ-11: Initial sync priority.** What decides what arrives first: the screen the user opened (Zero's query-driven sync), recency, object type, or a combination. How dependencies (`SYNC-G-306`) pull related data along. Whether the rest arrives in one pass or in pages. (Prior art: Linear's partial bootstrap, PowerSync's sync priorities.) Affects `SYNC-G-204`, `SYNC-G-205`.
- **OQ-12: Measuring connection quality.** Which signals define degraded and stalled: heartbeat round-trip time, time since the last server message, time for a command to be acknowledged. With which thresholds, hold periods and maximums. Affects `SYNC-G-1002`, `SYNC-G-1006`, `SYNC-G-1010`.
- **OQ-13: What a manual repair does with unsynced work.** Replay it against the fresh state, keep it aside for the user to review (keeping the pre-reset pending set until the user has seen the report, as Realm's reset hooks allow), offer to copy or export it (Todoist), or offer to discard it after confirmation. Whether the repair is offered only when something looks wrong or always. Affects `SYNC-G-804`.
- **OQ-14: Retention windows.** How long deletion records and idempotency keys are kept, and what happens to a client beyond them. Today: 7 days for deletions, effectively 24–48 hours for idempotency keys, which conflicts with `SYNC-G-102` and `SYNC-G-803`. Shortening a window is irreversible for clients already beyond it (Realm). Affects `SYNC-G-102`, `SYNC-G-303`, `SYNC-G-309`.
- **OQ-15: Losing access through your own change.** When a user's own valid mutation removes their access to an object, is that reported as a rejection, as a reported disappearance, or as normal confirmation? Affects `SYNC-S-028`, `SYNC-G-701`.

### Proposed answers

*Analysis of 2026-11-28, not yet decided.* The default is the obvious or most common answer in the prior art. "Reversibility" says how hard it would be to change the answer later. Questions marked **one-way** are decided together in the sync protocol v2 design (see [roadmap.md](roadmap.md)); the rest can adopt the default and be revisited freely.

| OQ | Proposed default | Reversibility |
|---|---|---|
| OQ-1 Cursor | A sync log table in Postgres with a counter assigned under a lock (Linear-like), written by database triggers so changes from any writer are captured (`SYNC-G-310`). | **One-way (medium).** The opaque cursor (`SYNC-G-318`) lets the server switch strategy behind a forced reset (`SYNC-G-309`), but the log table's shape and retention are harder to change. |
| OQ-2 Confirmation | The server records the last processed mutation ID per client (`lastMutationID`) and sends it with every catch-up response and live message (Replicache). Linear's approach of comparing cursor positions is ruled out by `SYNC-G-318`. | **One-way (medium).** A protocol change behind the version gate. |
| OQ-3 Overlay or replay | Replay (Replicache, game netcode, LiveStore). "Set these fields" is the most common intent and replays exactly like today's overlay. | **One-way (hardest).** Replay depends on the stored command format (`SYNC-G-408`), which deployed clients keep across updates (`SYNC-G-101`, `SYNC-G-807`). |
| OQ-4 After a rejection | Skip and continue (PowerSync, Replicache, current). Dependent mutations then fail on their own through `SYNC-G-505`; their reports are grouped. | Easy: client policy. |
| OQ-5 Merge rules | Last-writer-wins per field, server-ordered, as default; delete wins, and the losing edit is reported (`SYNC-S-004`). Collection additions already survive because members are separate objects. Counters and fractional indexing only when a feature needs them. | Adding rules: easy (`SYNC-G-510`). Changing the rule of a field in use: medium, it changes behaviour for users. |
| OQ-6 Convergence bound | Live update p95 under 1–2 s; catch-up of a typical workspace under 5 s. Tuned with the `SYNC-G-1101` metrics. | Trivial. |
| OQ-7 Multiple tabs | One shared IndexedDB queue; one tab, elected via Web Locks, flushes it; BroadcastChannel notifies the others; a lock-free fallback where Web Locks are missing. | Easy: client-only. |
| OQ-8 "Changed since I last looked" | The engine exposes who changed what and when; each device keeps its own "last viewed" record, not synced. | Easy. |
| OQ-9 Rejection reporting | A persistent list of failed mutations until acknowledged, keeping the payload so the user can retry or copy it. | Easy. |
| OQ-10 Overwritten values | Keep the user's value locally until acknowledged (Automerge-like). | Easy, provided base values are recorded from the start (`SYNC-G-408`). |
| OQ-11 Initial sync priority | What is on screen first, together with what it depends on, then the rest (Linear's partial bootstrap). | Medium: needs a scoped-fetch protocol. |
| OQ-12 Connection quality | Heartbeat every 10–15 s; stalled after two missed heartbeats; degraded when acknowledgements are slow. Hold period of 10 s, doubling on each flap up to 60 s (Fiedler). | Trivial. |
| OQ-13 Manual repair | Replay pending work against the fresh state (Realm's default), report what fails, and keep the pre-reset pending set until the user has seen the report. | Easy. |
| OQ-14 Retention | Deduplicate queued commands with the per-client `lastMutationID` from OQ-2 instead of time-limited idempotency keys: one number per client, kept indefinitely, which resolves the conflict with `SYNC-G-803`. Deletion records: about 30 days, then reset (Realm), or compaction if the OQ-1 log allows it. | **One-way for shortening**: clients already beyond a shortened window can't be helped. Lengthening is easy. |
| OQ-15 Own change hides something | Treat it as a normal confirmation; the client knows it issued the change and explains the disappearance itself. | Easy. |

## Coverage

*Planned, not built yet.*

Tests declare which IDs they cover:

- **RSpec:** metadata, `it "…", covers: %w[SYNC-G-302] do`
- **Vitest:** the ID in the test name, `it('[SYNC-G-402] keeps pending value while response is in flight', …)`
- **Playwright:** the `tag` option, `test('…', { tag: ['@SYNC-S-001', '@SYNC-G-503'] }, …)`

A script (no AI) builds the report from this document and the test runners' JSON output, so only tests that ran and passed count:

- **Covered:** each ID with the tests that cover it.
- **Uncovered:** IDs with no passing test. Reported; becomes a CI gate once the spec is agreed.
- **Unknown:** tags that point at an ID not defined here. Fails CI from day one.
- **Retired:** tags pointing at a retired ID. Fails CI, so stale tests get cleaned up.

A scenario counts as covered when an end-to-end test tagged with its ID passes. A guarantee needs its own tagged test; being listed under a covered scenario is not enough.

A tag only shows that a test *claims* to cover an ID. Whether it does is a review question; the report lists test names next to each ID to make that review quick.

### Testing methods

Example-based tests alone won't catch most sync bugs. The suite should also use:

- **Model-based tests** (fast-check `fc.commands`, with `fc.scheduledModelRun` to reorder in-flight promises) against a model of "server log plus pending queue". For 4xx and 6xx.
- **Deterministic simulation:** fake network, clock, local storage and WebSocket behind interfaces, driven by one seed; inject drops, duplicates, reordering and crashes at every `await`; print the seed on failure so the run can be replayed. For 1xx, `SYNC-G-316` and multiple tabs.
- **Postgres interleaving tests** with two database connections: open transaction A and write, commit B, sync, commit A, sync again, assert A arrives. Also hold an idle transaction open. For `SYNC-G-302` and `SYNC-S-012`.
- **Differential tests:** live versus catch-up, and full sync versus catch-up, from the same seeded history. For `SYNC-G-304` and `SYNC-G-315`.
- **Clock skew:** fake timers with the client clock offset by an hour either way. For `SYNC-P-7` and `SYNC-S-011`.
- **A standing impairment profile:** run the end-to-end scenarios under constant latency and packet loss, plus stalled WebSockets and dropped responses.
- **Upgrade tests** that start from a persisted cache and queue written by an older version, not from an empty store. For `SYNC-G-807`.
- **An engine-level switch** to force offline and inject faults, usable from tests.
- **A telemetry allowlist test:** every telemetry and error-report payload is validated against its schema, and unknown fields fail. For `SYNC-G-1107`.

## Related documents

To be reorganised once this spec settles: principles move here, implementation stays in the docs below, and guidelines become checklists that reference guarantee IDs.

- [roadmap.md](roadmap.md): how we get from the current engine to this spec, including the gap inventory method.
- [prior-art.md](prior-art.md): research behind the principles and open questions, including where sources disagree.
- [bugs-to-verify.md](bugs-to-verify.md): suspected bugs in the current engine, each to be confirmed with a failing test.
- `doc/backend-sync.md`: backend implementation (broadcasts, partial sync, `deleted_items`).
- `doc/offline-support.md`: frontend implementation (command queue, pool, persistence).
- `doc/connectivity-guidelines.md`: rules for writing code that stays responsive offline.
- `doc/protocol-versioning.md`: how breaking client/server changes ship.
- `doc/admin.md`: the operator-only admin site, the natural home for `SYNC-G-1103` and `SYNC-G-1106`.
