# Consistent task sorting across clients

## Problem

Task lists and task items are manually sortable via a float `position` column
(drag-and-drop, keyboard reorder). Positions can tie:

- `TaskLists::AddItem` / `TaskLists::Create` compute `max_position + 1.0` in a
  READ COMMITTED transaction — two clients adding concurrently (or replaying
  offline queues at the same time) read the same max and get identical
  positions.
- Two clients dragging different items into the same gap both compute the same
  `positionBetween` midpoint.

When positions tie, no layer breaks the tie deterministically:

- Postgres `ORDER BY position` returns tied rows in arbitrary order
  (`TaskItem.for_task_list(s)`, `TaskList.for_workspace`).
- The frontend comparators (`sortTaskItems.ts`, the task-list sort in
  `TasksPage.vue`) rely on JS stable sort, so ties fall back to each client's
  local object-pool insertion order — which differs per client depending on
  when objects arrived over the WebSocket.
- The History section sorts by `completedAt` alone; ties (e.g. a bulk sync
  stamping several completions with the same timestamp) fall back to pool
  order the same way.

Result: two clients looking at the same list can render tied items in
different orders, and the order can flip after a reload or resync.

## Design

Impose a deterministic total order on every sorting surface. Manual sorting is
untouched — `position` remains the primary key of the order; ties simply
resolve identically everywhere:

- **Order key**: `(position, createdAt, id)`. `createdAt` keeps tied items in
  intuitive creation order; `id` (UUID, lowercase hex — lexicographic string
  order matches Postgres uuid byte order) guarantees the order is total.
- **Backend**: `TaskItem.for_task_list`, `TaskItem.for_task_lists`, and
  `TaskList.for_workspace` order by `position, created_at, id`.
- **Frontend**:
  - `sortTaskItems` tie-breaks `position` with `createdAt` then `id`.
  - The task-list sort moves out of `TasksPage.vue` into a
    `sortTaskLists` helper (mirroring `sortTaskItems`) with the same
    tie-break.
  - `groupTaskItems`'s History sort tie-breaks `completedAt` with `id`.

Timestamps are compared as ISO-8601 strings on the frontend (the serializer
emits one uniform format, per the existing convention in `groupTaskItems`).
All clients sort the same serialized data with the same comparator, so they
converge to the same order regardless of arrival order.

## Alternatives considered

- **Prevent ties at the source** (advisory locks or `SERIALIZABLE` around
  position assignment): doesn't help offline/concurrent drags, adds contention,
  and still needs a tie-break for pre-existing ties. Rejected.
- **Integer positions with renumbering**: much bigger change (schema, rewrite
  fan-out on every reorder, more broadcast traffic) for no user-visible gain
  over fractional positions + deterministic tie-break. Rejected.

## Testing

- Frontend unit specs: tie cases for `sortTaskItems`, new `sortTaskLists`
  helper, History tie-break in `groupTaskItems`.
- Backend model specs: `TaskItem.for_task_list` / `TaskList.for_workspace`
  return tied positions ordered by `created_at`, then `id`.
