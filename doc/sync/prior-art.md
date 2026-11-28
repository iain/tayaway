# Sync Engine v2: prior art

Research notes for the sync engine spec. For each source: the problem it solves best, the mechanism, and what it suggests for Tayaway. This document is input to the spec, not part of it. Conclusions belong in the spec, and decisions stay open until we make them there.

Where a claim comes from a secondary source (reverse engineering, a summary of a talk) it is marked as such. Check the primary source before depending on a detail. Each section was reviewed in depth on 2026-11-28; the resulting changes are merged into [spec.md](spec.md).

## The shared pattern

Almost every system below that has an authoritative server ends up with the same loop. It is worth naming once, because the rest of this document is variations on it:

1. The client applies a change locally right away (*prediction*, *optimistic update*, *local mutation*).
2. The change goes into an ordered queue of unconfirmed operations, each with a client-assigned sequence number or ID.
3. The server applies operations in its own order, which becomes the truth, and reports which operations it has processed.
4. When authoritative state arrives, the client takes it as the new base and *replays the still-unconfirmed operations on top* (*reconciliation*, *rebase*).
5. Operations the server has confirmed are dropped from the queue. Operations it rejected disappear on the next rebase.

Game netcode calls this client-side prediction plus server reconciliation. Replicache calls it rebase. Tayaway currently does a simpler version: it overlays pending changes on server state and clears them based on timestamps, without replaying operations. See [Implications](#implications-for-tayaway). Not every system follows all five steps; see [Where sources disagree](#where-sources-disagree).

## Sources

### Linear

**Best at:** fast, local-first UI for structured business data, the closest product analogue to Tayaway.

**Mechanism:**
- An in-memory object graph (MobX), persisted to IndexedDB, hydrated at startup ("bootstrap"). Partial bootstrapping loads only what is needed first, then hydrates lazily.
- Each change is a transaction. Transactions are queued, persisted, and sent; those from the same tick are batched into one request. Optimistic changes live in memory only: IndexedDB model tables change only when server data arrives.
- Every change the server applies gets an ID in an **ordered sync action log**. Linear's own post describes a per-workspace log; the reverse-engineering study infers a database-wide counter. A client compares its last seen sync ID (`lastSyncId`) with the server's and fetches the missing *delta packets*. IDs have gaps, and a gap doesn't mean missing data. This is a sequence number, not a timestamp.
- **Confirmation by sync ID:** the server answers a mutation with the sync ID that will include it. The transaction counts as complete only once the client has received deltas up to that ID (`syncIdNeededForCompletion`); the HTTP response alone isn't trusted. *(Reverse-engineering study.)*
- When a user joins a sync group (gains access), the client runs a partial bootstrap of the newly visible data before continuing with deltas.
- The originating client receives its own change back like every other client.
- Conflict resolution is server-ordered last-writer-wins per field. A pending edit is rebased by replacing its original value with the incoming server value. *(Reverse-engineering study.)* CRDTs were added later, for rich-text issue descriptions only. *(Secondary: a blog citing a podcast.)*
- The catch-up read path was rebuilt in 2026: Postgres stays the authority for the most recent actions, overlapped with a lagging index and deduplicated by ID. The new path ran in shadow mode, comparing results with the old one, because "delta sync is a correctness-critical path".

**For Tayaway:** this is the architecture Tayaway resembles most: object pool, pool-shaped payloads, IndexedDB cache, WebSocket deltas. The main differences are the cursor (Linear catches up from a server-assigned sequence number, Tayaway from a wall-clock timestamp) and confirmation (Linear waits for its sync ID, Tayaway compares timestamps). Linear's CRDT-only-for-text choice is a useful precedent for keeping CRDTs out of the engine core.

**Sources:**
- [Rebuilding Linear's delta sync read path](https://linear.app/now/rebuilding-delta-sync-read-path) (Linear, 2026-08, the most detailed primary source on catch-up)
- [Scaling the Linear Sync Engine](https://linear.app/now/scaling-the-linear-sync-engine) (video of Tuomas Artman's talk; no written content)
- [reverse-linear-sync-engine](https://github.com/wzhudev/reverse-linear-sync-engine) (reverse-engineering study; Artman has publicly called it more complete than Linear's internal documentation)

### Replicache and Zero (Rocicorp)

**Best at:** precise, well-documented semantics for optimistic mutations against an authoritative server. The clearest formal model of the shared pattern.

**Mechanism:**
- All writes go through **named mutators**, implemented twice: once on the client (optimistic) and once on the server (authoritative). The server version may do more, for example authorization checks. The two need not match.
- Each client keeps a monotonically increasing **mutation ID**. The server stores `lastMutationID` per client, in the same transaction as the mutation. That value and the returned patch must be read in one snapshot, or users see data disappear or a mutation appear to run twice.
- **Pull** returns a patch against the client group's last **cookie** plus `lastMutationID` changes for every client in the group. The cookie is opaque to the client: a global version, a per-space version, or a client-view-record ID, depending on the server strategy. The client discards pending mutations at or below the confirmed ID, then **rebases**: replays the remaining pending mutations on top of the new server state.
- The docs state that a timestamp cursor "can't be done correctly", because parallel commits land behind it.
- **Poke**: the server sends a content-free hint over pub/sub telling clients to pull, with a periodic pull as fallback when a poke is lost. Catch-up and live updates share one code path. (Replicache also has an experimental data-carrying poke.)
- IDs are passed into mutators rather than generated inside, because a mutator can be replayed many times. Full determinism isn't required.
- A mutation the server rejects *permanently* is still marked as processed (its ID advances), so the client stops replaying it; a mutation that always errors would otherwise deadlock the client. *Temporary* errors deliberately block the queue. Replicache has no standard way to tell the client why a mutation was rejected; Zero reports it through the mutation's server promise.
- The **row-version strategy** keeps a client view record per client group and diffs it against the current view, which delivers deletes without tombstones and handles permission changes. With plain version cursors, a permission change doesn't bump row versions, so newly accessible data isn't sent.
- Unsent mutations were lost across a major-version upgrade (v8 to v9). An unknown mutator name is a silent no-op, so mutator names may only be added, never changed.
- **Zero** is the successor: the same mutator model plus a query language, with partial sync driven by the queries the client is running. Query results are typed `unknown`, `cached` or `complete`. Zero does **not** support offline writes: writes are rejected while disconnected, and its docs say it isn't designed for long periods offline. It is prior art for query-driven partial sync, not for offline use.

**For Tayaway:** Tayaway's commands are REST calls with diff-shaped optimistic updates, not replayable mutators. Rebasing becomes possible if each optimistic update can be re-derived from the command against new server state. The `lastMutationID` idea answers "is my change in this server state yet?" without comparing clocks. The poke idea is relevant because Tayaway has two catch-up paths (WebSocket push plus partial sync) that must agree. The row-version strategy is a candidate cursor that also covers visibility changes.

**Sources:**
- [How Replicache works](https://doc.replicache.dev/concepts/how-it-works) and [Consistency](https://doc.replicache.dev/concepts/consistency)
- [Remote mutations](https://doc.replicache.dev/byob/remote-mutations) and [Database isolation level](https://doc.replicache.dev/concepts/db-isolation-level)
- [Global version](https://trunk.doc.replicache.dev/strategies/global-version), [Row version](https://doc.replicache.dev/strategies/row-version) and [Reset](https://doc.replicache.dev/strategies/reset) strategies
- [Zero: mutators](https://zero.rocicorp.dev/docs/mutators) and [Zero: offline](https://zero.rocicorp.dev/docs/offline)

### Game netcode

**Best at:** making a system feel instant when every action needs server confirmation, and correcting mistakes without the user noticing. Directly relevant to "never surprised".

**Mechanism:**
- **Client-side prediction:** apply the player's input locally immediately.
- **Server reconciliation:** each input carries a sequence number. The server's authoritative state says which input it last processed. The client resets to that state and re-applies the inputs that are still unacknowledged. Gambetta notes that even with a deterministic world and no cheating, prediction and server state can still disagree, so reconciliation is always required.
- **No repeated side effects:** a replayed input must not replay its effects. Valve's client plays footstep sounds and similar effects only the first time a command runs.
- **Entity interpolation:** *other* players' state is shown slightly in the past and smoothed, because it can't be predicted. Your own actions are predicted, others' actions are interpolated. Two display strategies for two sources of change.
- **Don't predict contested outcomes:** damage and health are never predicted; the client waits for the server. Prediction is also cut back as latency grows (Valve caps extrapolation at 0.25 s; Overwatch reportedly turns hit prediction off at high ping).
- **Lag compensation (Valve):** the server rewinds its history to judge an action against what the client saw when it acted. Valve caps the rewind at 1 second and rewinds only players, and the cost lands on the other player, who can get shot "around a corner".
- **Rollback (GGPO, Overwatch):** save state snapshots, predict, and when a prediction was wrong roll back and resimulate. Per Infil, the hard parts are fast state save/load, separating game logic from rendering, and side effects that must not repeat; determinism is a precondition. Retrofitting rollback onto a game that didn't register all state for it was very expensive.
- **Connection quality (Fiedler):** smooth round-trip measurements, drop to a degraded mode immediately, return only after a sustained good period, and double that period when the connection keeps flapping. A steady delay is better than a variable one: players "lose confidence" when latency fluctuates.
- **Testing:** one fighting-game QA team kept 20% packet loss and 150 ms latency switched on permanently.

**For Tayaway:**
- Reconciliation by sequence number is the same pattern as Replicache, which confirms it.
- Treating "my changes" and "others' changes" differently in the UI is a direct input for "never surprised". Mine apply instantly and are marked unconfirmed. Others' arrive with a visible "changed by X" cue instead of silently replacing what I saw.
- "Don't predict contested outcomes" translates to: don't tell a user they got the last spot until the server agrees.
- The version the user saw (base version) is the hook for *detecting* that someone else changed something while they were offline. It is not what the server should validate against (`SYNC-G-505`); Valve's 1-second cap shows how far rewinding stretches.
- Replaying pending mutations must not repeat toasts, notifications or other effects.

**Sources:**
- [Gabriel Gambetta, Fast-Paced Multiplayer, Part II: Client-Side Prediction and Server Reconciliation](https://gabrielgambetta.com/client-side-prediction-server-reconciliation.html) (also [Part III: Entity Interpolation](https://gabrielgambetta.com/entity-interpolation.html) and the [live demo](https://www.gabrielgambetta.com/client-side-prediction-live-demo.html))
- [Valve: Source Multiplayer Networking](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking), [Lag Compensation](https://developer.valvesoftware.com/wiki/Lag_Compensation) and [Latency Compensating Methods](https://developer.valvesoftware.com/wiki/Latency_Compensating_Methods_in_Client/Server_In-game_Protocol_Design_and_Optimization) (Yahn Bernier). The wiki blocks automated fetches; use the Wayback Machine to check.
- [Overwatch Gameplay Architecture and Netcode](https://gdcvault.com/play/1024001) (Timothy Ford, GDC 2017). No English transcript; details come from secondary sources.
- Infil on netcode: [rollback explained (part 4)](https://words.infil.net/w02-netcode-p4.html) and [its costs (part 5)](https://words.infil.net/w02-netcode-p5.html); [GGPO](https://en.wikipedia.org/wiki/GGPO) and a [summary of Tony Cannon's "Fight the Lag!"](https://gamedeveloper.com/programming/the-lag-fighting-techniques-behind-ggpo-s-netcode)
- [Glenn Fiedler, Gaffer On Games](https://gafferongames.com/) networking articles (reliability, state synchronization, connection quality)

### Figma multiplayer

**Best at:** pragmatic conflict resolution for a tree of objects with properties, ordering children without conflicts, and real-time subscriptions over Postgres.

**Mechanism:**
- Client/server over WebSockets. The server is the authority and orders all changes; "we don't need a timestamp because the server can define the order".
- The document is a tree of objects. Conflicts resolve **last-writer-wins per property, as ordered by the server**, not per object and not by client clock. Two people changing different properties of one object both win.
- They looked at OT and CRDTs and took the CRDT ideas without the full machinery, because a central server makes it unnecessary.
- The client **discards any incoming server change** (its own echo or someone else's) to a property that has an unacknowledged local change, so its local value doesn't flicker back.
- Reconnecting downloads a fresh copy of the document and reapplies offline edits on top; connect and reconnect share one path.
- Writing a property of an unknown object doesn't create it; an object's existence is its own value. A node's parent and its position are stored as **one property**, so they change atomically.
- Ordered children use **fractional indexing**: each child has a position between its neighbours' positions (arbitrary-precision strings), so concurrent inserts and moves don't conflict. The server fixes collisions.
- The server rejects reparenting that would create a cycle; the client hides affected objects until it is resolved.
- Every change is written to a **journal** (write-ahead log) before it is considered saved. Autosave keeps unsynced edits on disk for crash recovery; it buffers in memory first, so there is a short loss window. A bug where a no-op write didn't fire observers left confirmed changes on disk, where they later overwrote newer edits.
- **LiveGraph**, Figma's real-time subscription service for non-document data, tails Postgres logical replication. Its first version relied on change events emitted by hand at each write site, which proved hard to reason about; ordering, permission cascades and reconnect storms after deploys were recurring problems. It verifies its cache against the database online.

**For Tayaway:**
- Per-property LWW with *server* ordering is a strong default for scalar fields (event title, date, location).
- Discarding incoming values for properties with an unacknowledged local change is exactly the flicker problem Tayaway's pending-update logic handles with timestamp comparisons.
- Fractional indexing applies directly to any ordered list (task items, chores) if manual reordering exists or is planned.
- LiveGraph's lesson applies directly: Tayaway's manual `Broadcaster` calls at each write site are the pattern Figma moved away from.

**Sources:**
- [How Figma's multiplayer technology works](https://madebyevan.com/figma/how-figmas-multiplayer-technology-works/) (Evan Wallace, 2019)
- [Realtime editing of ordered sequences](https://www.figma.com/blog/realtime-editing-of-ordered-sequences/) (fractional indexing)
- [Making multiplayer more reliable](https://www.figma.com/blog/making-multiplayer-more-reliable/) (the journal)
- [Behind the feature: the hidden challenges of autosave](https://www.figma.com/blog/behind-the-feature-autosave/)
- [LiveGraph: real-time data at scale](https://www.figma.com/blog/livegraph-real-time-data-at-scale/) and [LiveGraph: real-time data fetching at Figma](https://www.figma.com/blog/livegraph-real-time-data-fetching-at-figma/)

### Local-first research (Ink & Switch, Automerge, Yjs)

**Best at:** defining the ideals, and the theory of merging without a central authority (though the essay is fine with servers acting as "cloud peers").

**Mechanism and ideas:**
- The *Local-first software* essay (2019) proposes seven ideals: "No spinners", "Your work is not trapped on one device", "The network is optional", "Seamless collaboration with your colleagues", "The Long Now", "Security and privacy by default", and "You retain ultimate ownership and control". Kleppmann later said these "aren't really a good definition" of local-first and proposed instead that "the availability of another computer should never prevent you from working" (Local-First Conf 2024, via PowerSync's blog).
- CRDTs (Automerge, Yjs) merge concurrent edits without coordination: sets, counters, lists, and text, each with defined merge semantics. Automerge keeps losing values in a conflicts object until the next write resolves them.
- The costs the essay names are accumulated change history (memory, disk) and schema migration as an open problem. On conflicts it reports: "Conflicts are not as significant a problem as we feared." It also found the default merge semantics sufficient: no case needed custom rules.
- Loss of user intent despite a clean merge comes from Kleppmann's later work: merges that converge can still interleave concurrent insertions, and a move done as delete plus re-insert duplicates the item under concurrent moves (and concurrent tree moves can create cycles). Peritext notes merges "won't always perfectly capture user intent".
- Cambria translates data between schema versions at read time, so old and new app versions can work together. Upwelling explores private drafts before sharing.
- Browser storage is unsuitable for data of long-term importance; Safari deletes script-writable storage after 7 days without interaction for web apps not added to the home screen.

**For Tayaway:**
- The first four ideals line up with the user's goals (instant, offline, real-time collaboration). Longevity, privacy and ownership are probably out of scope and should be stated as such.
- CRDT semantics are a vocabulary for *per-field merge rules* even without a CRDT library: "add-wins set" for list membership, "counter" for tallies, "LWW register" for scalars. The spec can specify behaviour in these terms and leave the implementation open.
- Moves must be atomic, and browser storage can disappear: both need explicit guarantees.

**Sources:**
- [Local-first software: you own your data, in spite of the cloud](https://inkandswitch.com/local-first/) (Kleppmann, Wiggins, van Hardenberg, McGranaghan)
- Kleppmann et al., *Interleaving anomalies in collaborative text editors* (PaPoC 2019) and *A highly-available move operation for replicated trees*
- [Peritext](https://www.inkandswitch.com/peritext/), [Cambria](https://www.inkandswitch.com/cambria/), [Upwelling](https://www.inkandswitch.com/upwelling/)
- [Automerge: conflicts](https://automerge.org/docs/reference/documents/conflicts/)
- [WebKit: full third-party cookie blocking and more](https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/) (the 7-day storage cap)
- [PowerSync: Local-first software origins and evolution](https://powersync.com/blog/local-first-software-origins-and-evolution)

### Firestore and Realtime Database

**Best at:** exposing sync state to the UI as data.

**Mechanism:**
- Every document and query snapshot has metadata with two independent flags:
  - `hasPendingWrites`: the snapshot includes local writes not yet committed on the server.
  - `fromCache`: the data came from the local cache, so it may be stale *or incomplete*.
- Listeners can opt into metadata-only changes (off by default), so the UI is told when a pending write gets confirmed even if the data didn't change. There are also client-wide signals: `waitForPendingWrites` and `onSnapshotsInSync`.
- Offline writes are queued and synchronized on reconnect; for several changes to the same document, last write wins. (Per-client ordering isn't stated in the docs.) Transactions fail offline; batched writes are queued.
- A pending server timestamp reads as a local estimate, the previous value, or null, depending on an option.
- Uncached data: a collection query returns *empty* rather than an error.
- The local cache isn't cleared between sessions; the docs advise asking whether the device is trusted.
- **Realtime Database:** `.info/connected` exposes connection state per client; writes pause when authentication expires and resume after re-authentication; offline transactions are *not* persisted across app restarts.

**For Tayaway:** the distinction between "unconfirmed because of me" (`hasPendingWrites`) and "possibly stale or incomplete because I'm not caught up" (`fromCache`) is exactly what "never surprised" needs, per object and per screen rather than one global badge. Tayaway's pool knows the first (pending updates) but doesn't expose it per object, and doesn't track the second at all apart from the global connection badge. The empty-collection behaviour is the pitfall `SYNC-G-205` forbids.

**Sources:**
- [Firestore: access data offline](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
- [Firestore: listen to realtime updates](https://firebase.google.com/docs/firestore/query-data/listen) and [transactions](https://firebase.google.com/docs/firestore/manage-data/transactions)
- [Firestore SnapshotMetadata](https://firebase.google.com/docs/reference/js/firestore_.snapshotmetadata) and [SnapshotOptions](https://firebase.google.com/docs/reference/js/firestore_.snapshotoptions)
- [Realtime Database: offline capabilities](https://firebase.google.com/docs/database/web/offline-capabilities)

### PowerSync

**Best at:** a precise consistency model for "local SQLite synced from Postgres, writes through your own API". The closest *infrastructure* match to Tayaway's server-authoritative REST write path.

**Mechanism:**
- Writes go into a local **upload queue**, uploaded through the app's own backend API. Each local transaction is uploaded as one transaction. The queue is FIFO and doesn't advance until the backend acknowledges the head.
- A **permanent rejection** is meant to be acknowledged with 2xx, so the queue moves on: skip and continue, like Tayaway. Recording the rejected write in a dead-letter table is optional bookkeeping. The client isn't told: its local change stays until the upload queue is empty and is then silently replaced by server state. A blocked queue is the failure mode for retryable or mishandled errors, and the docs warn that a backlogged queue delays all new data.
- Downloads arrive as **checkpoints**: consistent snapshots of server state at a replication position, applied only once all their data has arrived.
- **The client does not apply a new checkpoint while it has pending uploads.** Once the queue is empty it requests a *write checkpoint*: a checkpoint guaranteed to include its own writes. So a sync never reverts pending changes, and the client never has to resolve conflicts locally. Exceptions: priority-0 data syncs regardless (and may flicker), and with sync priorities, deletes and rollbacks wait until all priorities have synced. Newer *checkpoint requests* (alpha) are replacing write checkpoints.
- Per-bucket **checksums**: on mismatch the client deletes the bucket and resyncs it. History is **compacted** rather than expired, so a long-offline client downloads only incremental changes.
- Conflict handling: per-field last-writer-wins in server-receipt order; deletes win. Timestamp-based conflict detection is called unreliable because of clock skew.
- Multi-tab on the web: one shared worker holds the connection; without shared workers (iOS Safari) only one tab syncs at a time.
- The documentation calls the result *causal+ consistency*, without defining it beyond a link to Jepsen.

**For Tayaway:**
- The write-checkpoint idea is an alternative to rebasing: avoid ever showing a server state that doesn't yet include my writes. Its hidden cost is that a stuck queue withholds everyone else's changes.
- PowerSync handles a permanent rejection the way Tayaway does: skip and continue. Its silent revert is what "never surprised" must improve on.
- Checksums are a model for detecting client/server divergence; compaction is an alternative to the 7-day `deleted_items` window.

**Sources:**
- [PowerSync: Designed for causal+ consistency](https://docs.powersync.com/architecture/consistency)
- [PowerSync protocol](https://docs.powersync.com/architecture/powersync-protocol)
- [Checkpoint requests](https://powersync.com/blog/checkpoint-requests-client-synced-now)
- The write path (rejected writes, blocked transactions, conflicts), prioritized sync, checksums and multi-tab are documented across several pages; the [full docs as one file](https://docs.powersync.com/llms-full.txt) is the easiest way to search them.

### ElectricSQL and TanStack DB

**Best at:** read-path sync of Postgres subsets ("shapes"), and a clear taxonomy of write strategies.

**Mechanism:**
- Electric only syncs *reads*. Writes go through your own API, the same as Tayaway.
- Their write-patterns guide describes four levels: online writes, optimistic state per component, shared persistent optimistic state, and full local-first through an embedded database. Each level is more robust and more complex. A write counts as confirmed only once it has returned *and* synced back.
- The writes guide matches pending writes against synced rows by a write ID. **TanStack DB**'s Electric collection instead has the API return the Postgres **transaction ID** and keeps optimistic state until a row from that transaction syncs (`awaitTxId`). The ID must be read inside the write's own transaction, and `::xid` is a 32-bit value that wraps.
- Rejecting one write and wiping all local state is called an "extremely naive strategy"; better is dropping only dependent writes or flagging them for review.
- Shapes are single-table subscriptions with a WHERE clause (which can use subqueries) and a column selection, the unit of partial replication. With subqueries, rows move in and out of a shape without themselves changing.
- A `must-refetch` response tells clients to discard local data and resync. Losing server history made every client resync at once; cached error responses and CDNs ignoring cursor parameters served stale data.
- Electric was rebuilt ("Electric Next") dropping finality of local writes: it "embraces tentativity", which removed the need for its complex permission system.

**For Tayaway:** `awaitTxId` is another answer to "when do I drop my pending update?" without comparing timestamps: the server tells the client which version will contain the write. The write-patterns taxonomy is a good way to state, in the spec, which level Tayaway commits to (it is at level 3). The caching pitfall applies to a PWA with a service worker.

**Sources:**
- [Electric: Writes guide](https://electric.ax/docs/guides/writes), [Shapes](https://electric.ax/docs/guides/shapes), [HTTP API](https://electric.ax/docs/api/http), [Troubleshooting](https://electric.ax/docs/guides/troubleshooting)
- [Electric Next](https://electric.ax/blog/2024/07/17/electric-next) and [Reliability sprint](https://electric.ax/blog/2025/08/04/reliability-sprint)
- [TanStack DB: mutations](https://tanstack.com/db/latest/docs/guides/mutations), [Electric collection](https://tanstack.com/db/latest/docs/collections/electric-collection), [offline transactions](https://tanstack.com/db/latest/docs/guides/offline-transactions)

### Realm / Atlas Device Sync

**Best at:** mature, documented handling of the *unhappy paths* that most sync engines skip: rejected writes and unrecoverable client state. The product was deprecated in September 2024 and removed on 30 September 2025; its docs remain a rich record of production lessons.

**Mechanism:**
- **Compensating writes:** when the server rejects a client write (for example permissions), it syncs back an *undo* operation and sends an error listing the affected writes and the reason. Later client writes to the *same object* made before the compensating write arrives are lost; writes to other objects are kept.
- **Client reset:** when the server can no longer sync with a client's local state, the client must reset. Causes include the server restoring from a backup, sync being terminated and re-enabled, a breaking schema change, a permission or role change, and exceeding the **client maximum offline time** (history older than the window is trimmed; default 30 days). Four modes: recover, recover or discard (the SDK default, which discards local changes if recovery fails), discard, and manual. Reset hooks get a read-only snapshot of the state before the reset.
- **Conflict rules** (verified in the docs): deletes always win; last update wins per property; list inserts are ordered by time; primary keys define identity. Special cases: counters merge as increments, strings as whole values, removing a dictionary key counts as an update, and updating a parent overwrites a nested collection.
- Trimming history is irreversible: raising the offline window only helps once new history has built up.
- Progress notifications report an estimate from 0 to 1, either for currently outstanding work or indefinitely.

**For Tayaway:**
- "Compensating write" names exactly what happens when a queued command fails: the optimistic state must be undone, and the user must be told *why* and *what was lost*, including later edits that built on it.
- "Client reset with recovery" is the case for a client offline longer than the 7-day `deleted_items` retention, or one whose `CACHE_VERSION` changed: today that is a full sync. Realm's default of discarding when recovery fails is what `SYNC-G-801` must not do.

**Sources:**
- [Device Sync errors (compensating writes)](https://mongodb.com/docs/atlas/app-services/sync/error-handling/errors)
- [Client resets](https://mongodb.com/docs/atlas/app-services/sync/error-handling/client-resets) and [client reset data recovery](https://mongodb.com/docs/atlas/device-sdks/sdk/node/sync/client-reset-data-recovery)
- [Conflict resolution](https://mongodb.com/docs/atlas/app-services/sync/details/conflict-resolution)
- [Optimize Sync usage (client maximum offline time)](https://mongodb.com/docs/atlas/app-services/sync/go-to-production/optimize-sync-atlas-usage)

### CouchDB / PouchDB

**Best at:** multi-master replication where conflicts are kept, not discarded, and a robust changes feed.

**Mechanism:**
- Every document has a revision tree. When replicas diverge, the conflicting revisions are kept as leaves. A **deterministic** algorithm picks the same winner on every replica without coordination: longest revision history wins, ties go to the highest revision ID. `_conflicts` lists the losing revision IDs when asked (`?conflicts=true`); their bodies are fetched separately. Compaction discards non-leaf bodies, so there is no history.
- The **changes feed** uses a sequence that may be any JSON value, so clients store it and send it back without interpreting it. A clustered feed may repeat changes, and only the latest change per document is guaranteed, so intermediate states can be skipped.
- Replication writes its checkpoint only after the batch is durably committed.
- A delete leaves a **tombstone**, required for the delete to replicate. Cleaning tombstones up (purge) is hard: a stale peer can bring deleted documents back.
- With filtered replication, documents that stop matching the filter stay on the client and never appear in the changes feed again.
- Browser storage pitfalls: quota, private-mode IndexedDB failures, browser eviction.

**For Tayaway:** a server-authoritative design doesn't need multi-master replication, but several ideas carry over: the changes feed is a model for `OQ-1` (opaque sequence, checkpoint after a durable write), tombstones for `SYNC-G-303`, and the filtered-replication pitfall for `SYNC-G-701`. Also: *don't silently destroy the losing side of a conflict*, which is what makes "your offline edit was overwritten by X, here's what you had" possible.

**Sources:**
- [CouchDB: Replication and conflict model](https://docs.couchdb.org/en/latest/replication/conflicts.html), [replication protocol](https://docs.couchdb.org/en/latest/replication/protocol.html), [`_changes`](https://docs.couchdb.org/en/latest/api/database/changes.html), [purging](https://docs.couchdb.org/en/latest/cluster/purging.html)
- [CouchDB: The Definitive Guide, conflicts](https://guide.couchdb.org/draft/conflicts.html)
- [PouchDB: Conflicts guide](https://pouchdb.com/guides/conflicts.html) and [filtered replication](https://pouchdb.com/2015/04/05/filtered-replication.html)

### LiveStore

**Best at:** event sourcing on the client.

**Mechanism:**
- The source of truth is an ordered **event log**. State (SQLite) is a materialized view of it.
- Local events are committed and materialized immediately, then pushed. Clients assign sequence numbers; the backend accepts a push only if it continues its current head, otherwise the client must pull and rebase. The backend doesn't validate or reject events, so outcomes are decided on the client.
- When remote events arrive, the client **rebases**: rolls back its unpushed local events, applies the remote ones, replays the local ones. It replays the recorded *events*, not the intent behind them. RFC 0002 proposes replaying commands (intent) instead, because blind rebase gives "convergence without correctness".
- One leader per client, elected with Web Locks, owns persistence and sync; tabs talk to it through a SharedWorker. Android Chrome has no SharedWorker, so LiveStore falls back to single-tab mode.
- A materializer error halts the store, and the only recovery is clearing storage, which loses unpushed events. A backend reset is detected through a backend ID; by default the client then clears local storage, unpushed events included.
- Event definitions can never be removed; only forward-compatible changes are allowed.

**For Tayaway:** not a pure form of the shared pattern after all, since the server never rejects. Useful as a model for *testing* (if state is a function of an ordered log, "two clients that saw the same log show the same state" is checkable), for multi-tab coordination, and as a source of pitfalls.

**Sources:**
- [LiveStore: syncing](https://docs.livestore.dev/building-with-livestore/syncing/) and [How LiveStore works](https://docs.livestore.dev/overview/how-livestore-works/)
- [RFC 0002: Command replay](https://github.com/livestorejs/livestore) (in the repository's contributor docs)

### Jazz

**Best at:** permission changes as part of the sync model.

**Mechanism:**
- **Jazz 2** (in beta, 2026) is a relational database with row-level policies checked only by the server. Clients get filtered rows and rejected writes, with no permission information attached.
- Access comes from membership rows, so objects enter and leave a user's view without changing themselves. The server re-evaluates subscriptions when a write or policy change could affect them.
- When a member is removed, online clients lose the data right away. An offline client keeps it readable until it reconnects; its queued writes are then rejected and reverted. Removing access "stops future reads, not past ones".
- Signing out keeps local data by default; each account gets its own local database.
- **Classic Jazz** (now archived) modelled access with Groups that own collaborative values, enforced cryptographically: removing a member rotated keys, and removed members kept what they already had.

**For Tayaway:** Tayaway ships per-recipient permissions in the payload (`PermissionAttacher`), which goes beyond Jazz 2. The open areas are *visibility changes*: someone removed (or added) while offline, and objects whose visibility changes without the objects themselves changing.

**Sources:**
- [Jazz: group permissions recipe](https://jazz.tools/docs/recipes/access-control/group-permissions) and [policies](https://jazz.tools/docs/schemas/policies)
- [Classic Jazz (archived)](https://github.com/garden-co/classic-jazz)

### Notion offline mode

**Best at:** product decisions on *which* data is available offline.

**Mechanism:**
- Pages are available offline for explicit *reasons*: the user toggled it, it's a favourite, or it's inherited through a database (only the first 50 rows are downloaded automatically). A table records one row per reason, and a page is evicted only when no reason remains. Automatic download of recent and favourite pages is a paid feature, and offline access is per device.
- Offline, only fully downloaded pages can be opened.
- Offline pages are migrated to a CRDT data model for rich-text conflict resolution.
- The server pushes updates for offline pages. On reconnect the client compares its download timestamps against server update times; live invalidation uses per-record versions.
- Operations are batched into transactions committed or rejected by the server as a group, sent one after another.
- Several tabs writing to OPFS SQLite corrupted it; the fix was a single writer chosen via SharedWorker, with Web Locks to detect closed tabs. On slow devices reading from disk was slower than the network, so Notion races the two.
- Users get positive confirmation: a sync indicator confirms everything is up to date. Sharing and permission changes are disabled offline.

**For Tayaway:** Tayaway currently caches the whole workspace, which is simpler and probably right at its scale. Notion is the reference if partial availability ever becomes necessary. It also shows that "what's available offline" and "everything is saved" are things to *show* the user, and that some actions are honestly online-only.

**Sources:**
- [How we made Notion available offline](https://notion.com/blog/how-we-made-notion-available-offline)
- [The data model behind Notion's flexibility](https://www.notion.com/blog/data-model-behind-notion)
- [How we sped up Notion in the browser with WASM SQLite](https://www.notion.com/blog/how-we-sped-up-notion-in-the-browser-with-wasm-sqlite)

### Idempotency keys (Stripe)

**Best at:** making retries safe on an unreliable network.

**Mechanism:**
- The client generates a unique key per logical request and sends it with every retry. Once execution begins, the server stores the result for that key (including server errors, but not validation failures or concurrent conflicts) and returns it for later attempts, so a retry after a lost response doesn't apply the change twice.
- Keys can be pruned once they are at least 24 hours old: a minimum, not a fixed window. Brandur suggests about 72 hours.
- The IETF draft for the `Idempotency-Key` header specifies 409 for a duplicate that is still in flight (the one error a client may retry unchanged) and 422 for a reused key with a different payload.
- Store the key in the same transaction as the work; effects outside the database should be staged in that transaction and sent afterwards.
- Retries need exponential backoff with jitter; without jitter, clients that failed together retry together.

**For Tayaway:** `Idempotency.wrap` covers every mutating route in `backend/app/routes/api.rb`, and create services also tolerate replays on the client-generated ID. There are gaps, including keys that change when queued commands are merged and a 24–48 hour effective retention: see [bugs-to-verify.md](bugs-to-verify.md). The spec should state the guarantee (each queued command takes effect at most once, even across retries and reloads) and its limits.

**Sources:**
- [Stripe: Designing robust and predictable APIs with idempotency](https://stripe.com/blog/idempotency) and [idempotent requests](https://docs.stripe.com/api/idempotent_requests)
- [Brandur Leach: Implementing Stripe-like idempotency keys in Postgres](https://brandur.org/idempotency-keys)
- [IETF: The Idempotency-Key HTTP Header Field](https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/)
- AWS Builders' Library: [Making retries safe with idempotent APIs](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/) and [Timeouts, retries, and backoff with jitter](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/)

## Cross-cutting themes

Ideas that come up in several sources independently, and so are strong candidates for spec principles:

| Theme | Seen in | What it means |
|---|---|---|
| Server-assigned order, not client clocks | Linear, Replicache, Figma, PowerSync, Electric, CouchDB | Truth is ordered by the server: sequence numbers, versions or transaction IDs. Client timestamps are for display only. |
| Confirmation by ID, not by comparison | Linear (sync ID), Replicache (`lastMutationID`), game netcode (input sequence), Electric/TanStack DB (`awaitTxId`), PowerSync (write checkpoint) | The client knows its operation is included because the server says so, not because a timestamp looks newer. |
| Replay unconfirmed operations on new state | Replicache, game netcode, LiveStore, Overwatch | Optimistic state is re-derived from operations, not kept as a stale diff. |
| Per-property merge, not per-object | Figma, Linear, Realm, PowerSync | Concurrent edits to different fields both survive. |
| Rejections are first-class events | Realm (compensating write with reason), Zero (reported via promise), Replicache (processed no-op) | A rejected write is undone visibly, with a reason, and doesn't block or corrupt the queue. PowerSync's silent revert is the counter-example. |
| Sync state is data the UI can read | Firestore (`hasPendingWrites`, `fromCache`), Zero (query result types), Notion (sync indicator) | Pending, stale and confirmed are queryable per object. |
| Reset is a designed path | Realm (client reset), Replicache (reset strategy), Electric (`must-refetch`) | "Too far behind" and "incompatible version" are recoverable, without silently losing local work. |
| Keep the losing side | CouchDB, Automerge, Realm (warns about loss) | Overwritten user work is at least detectable, so the UI can say so. |
| Own vs others' changes shown differently | Game netcode (prediction vs interpolation), Apple Notes and Upwelling (highlighting others' edits) | Instant for mine, smooth and attributed for theirs. |

## Where sources disagree

The themes above are where sources converge. These are the points where they make different choices, which is where Tayaway has to decide rather than copy. Each points at the spec question it bears on.

| Question | Positions | Bears on |
|---|---|---|
| **Offline writes at all?** | Full offline writes: Linear, Replicache, PowerSync, Realm, LiveStore, Firestore. Reads only, block input while offline: Zero. | `SYNC-P-1` (decided: full) |
| **Who decides the outcome?** | Server decides and can reject: Replicache, Linear, Figma, PowerSync, Realm, Jazz 2. Client decides, server only relays and orders: LiveStore, Automerge/Yjs. Every replica decides deterministically: CouchDB. | `SYNC-P-2` (decided: server) |
| **What happens to pending changes when server state arrives?** | Replay them on top: Replicache, game netcode, LiveStore. Keep them as an overlay and rebase the original value: Linear. Discard incoming values that conflict with them: Figma. Hold server state back until they're confirmed: PowerSync. | `OQ-3` |
| **What to do with later changes after a rejection?** | Skip and continue: PowerSync, Replicache (permanent errors), Tayaway today. Block until resolved: Replicache (temporary errors). Lose later edits to the same object only: Realm. Reject dependants too: Jazz. Flag dependants for review: Electric's guide. Wipe local state: called naive by Electric. | `OQ-4` |
| **Is the user told about a rejection?** | Yes, with a reason: Realm, Zero, Notion (toasts). No, silent revert: PowerSync by default, Replicache (no standard channel). | `SYNC-G-601`, `OQ-9` |
| **Delete versus concurrent edit** | Delete wins silently: Realm, PowerSync, Jazz (edit accepted, row stays deleted). Existence is its own last-writer-wins value: Figma. Reject the edit and report it: Tayaway's `SYNC-S-004`. | `SYNC-S-004`, `OQ-5` |
| **How a client catches up** | Incremental from a cursor: Linear, Replicache, CouchDB, PowerSync. Full re-download plus replay of offline edits: Figma documents. | `OQ-1`, full-vs-catch-up equivalence |
| **What the cursor is** | Ordered sync-action log ID: Linear. Opaque cookie per client group (global version, space version or client-view record): Replicache. Replication position: PowerSync, Figma LiveGraph. Opaque JSON sequence: CouchDB. Per-record versions: Notion. | `OQ-1` |
| **How long history is kept** | Trimmed, clients beyond the window reset: Realm (30 days default), Tayaway (7 days). Compacted, no offline limit: PowerSync. Kept indefinitely: local-first CRDTs. Idle clients garbage-collected after 24h: Replicache. | `SYNC-G-803`, retention |
| **Where CRDTs belong** | Everywhere: Automerge, Yjs. Only for rich text: Linear, Notion. Inspired by, not used: Figma. Not at all: Replicache, PowerSync, Realm. | `OQ-5`, out of scope |
| **Do permissions reach the client?** | Attached per recipient: Tayaway. Never sent, server-only: Jazz 2, Zero. Enforced cryptographically: classic Jazz. | `SYNC-G-702` |
| **What a permission change does** | Live re-evaluation, objects added and removed: Jazz 2, PowerSync. Forced client reset: Realm. Manual cache version bump: Tayaway today. | `SYNC-G-702`, `SYNC-G-701` |
| **Where optimistic state is stored** | In memory only, queue persisted, cache holds server data only: Linear. Buffered in memory, written periodically: Figma autosave. Written before the request: Tayaway. Not persisted at all: Electric pattern 2. | `SYNC-G-101` |
| **What sign-out does with local data** | Kept by default: Jazz, Zero, Firestore. Cleared, but only after the queue is empty: PowerSync's advice. Warn before discarding: Todoist. | Proposed user-switch guarantee |
| **Multiple tabs** | One leader tab owns sync (Web Locks / SharedWorker): LiveStore, Notion, TanStack DB, PowerSync. Single tab by default, multi-tab opt-in: Firestore. | `OQ-7` |
| **How common are conflicts?** | Rarer than feared: Ink & Switch, Electric (quoting Adam Wiggins), Linear (by its choices). They grow with time offline and resolutions won't always satisfy users: Replicache. "Offline mutations should never be rejected", or users lose large amounts of work: a Rocicorp engineer on Zero. | `OQ-9`, `OQ-10` |
| **Should conflicts be visible?** | Hidden by default, winner picked: CouchDB, Realm. Shown so the user can decide: Automerge's conflicts object, Peritext, PowerSync's optional conflicts table. | `SYNC-G-504`, `OQ-10` |
| **How much to predict** | Predict almost everything: Overwatch (by default), most app engines. Never predict contested outcomes, wait for the server: damage in shooters, rollback games' irreversible events. | Proposed "contested outcomes" guarantee |

## Implications for Tayaway

Observations from a first look at the current engine, set against the themes above. These are not yet a gap inventory: they are candidates for one, to verify once the spec exists. Concrete suspected bugs are tracked in [bugs-to-verify.md](bugs-to-verify.md).

- **The catch-up cursor is a wall-clock timestamp.** Partial sync returns rows with `updated_at` after the client's `since`, and `syncedAt` is the server's `Time.now`. A transaction that started before `syncedAt` but commits after it has an `updated_at` earlier than the new cursor, and the next partial sync can skip it. The sources that use a server-assigned sequence (Linear, Replicache, PowerSync) avoid this by design.
- **Pending updates are cleared by comparing clocks.** `importObjects` drops a pending update when the server object's `updatedAt` is newer than when the pending update was created on the client. That compares a server timestamp with a client timestamp. Confirmation by ID (sync ID, `lastMutationID`, transaction ID) would remove the clock dependency.
- **Optimistic state is an overlay, not a replay.** Pending diffs are merged on top of server data. That works for scalar fields, but can't express "add item to list" applied to a list that changed on the server meanwhile. Replay-based reconciliation (or per-field merge rules) would.
- **Failed commands are dropped and the queue moves on.** PowerSync does the same; Realm undoes later edits to the same object and says why. The UI side today is a toast; the spec should say what the user sees and what happens to dependent changes.
- **Sync state is global, not per object.** The connection badge and the pending-count toast are global. Firestore-style per-object `pending` / `stale` state would enable per-item indicators, which is the core of "never surprised".
- **Reset paths exist but aren't specified as such.** Retention expiry (7 days) and `CACHE_VERSION` bumps both lead to a full sync, and a full sync clears all pending updates.
- **Idempotency covers every mutating route, with gaps.** Merging queued commands changes the key, and keys effectively live 24–48 hours.
- **Changes are announced by hand.** Every service calls `Broadcaster` itself, the pattern Figma's LiveGraph moved away from.
- **Domain coupling lives in a few known places.** `CASCADE_RULES` in the object pool and the per-type `changed_since` methods are where domain knowledge enters the engine. A domain-agnostic engine would take these as registration data (as `ObjectRegistry` already does on the backend), not hard-code them.

## Further reading

Not reviewed in depth, but likely useful when writing specific spec sections:

- Martin Kleppmann, *Designing Data-Intensive Applications*: chapters on replication, consistency models, and ordering. The vocabulary for writing guarantees precisely (read-your-writes, monotonic reads, causal consistency).
- Terry et al., *Session Guarantees for Weakly Consistent Replicated Data* (1994): read-your-writes, monotonic reads, writes-follow-reads, monotonic writes.
- Lamport, *Time, Clocks, and the Ordering of Events in a Distributed System* (1978): why client clocks can't order events.
- [Jepsen consistency models](https://jepsen.io/consistency): a map of models and anomalies, and a model for fault-injection testing.
- [Liveblocks: Understanding sync engines: how Figma, Linear and Google Docs work](https://liveblocks.io/blog/understanding-sync-engines-how-figma-linear-and-google-docs-work): a side-by-side comparison of three approaches.
- Competitor offline UX (Todoist, Google Docs, Apple Notes, Things) was partly reviewed from vendor docs (see the Notion section). Linear's offline documentation no longer exists, so Linear still needs a hands-on look.
