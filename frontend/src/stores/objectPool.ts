import { ref, computed, triggerRef, toRaw } from 'vue'
import { defineStore } from 'pinia'
import {
  OBJECT_TYPES,
  type ObjectType,
  type ObjectTypeMap,
  type PoolObject,
  type PendingUpdate,
} from '@/types/pool'
import type { PoolUpdate } from '@/types/poolUpdate'
import { Scope } from '@/api/scope'
import { useWorkspaceStore } from './workspace'

export { Scope }

// Helper to compare ISO8601 timestamps
// ISO 8601 strings with the same format are lexicographically sortable
function isNewer(a: string, b: string): boolean {
  return a > b
}

// A copy carrying viewer-scoped `permissions` is strictly more complete than
// one without, even at the same version. The personal and workspace syncs
// serialize the same workspace/member row without and with permissions
// respectively (permissions depend on the viewer's membership, which only the
// workspace-scoped path attaches), and both share the row's updatedAt. Without
// this, whichever copy lands first wins the tie and the permissioned one can be
// dropped — hiding permission-gated UI like the Invite Members button.
function upgradesPermissions(
  incoming: PoolObject,
  existing: PoolObject
): boolean {
  return (
    incoming.updatedAt === existing.updatedAt &&
    incoming.permissions != null &&
    existing.permissions == null
  )
}

// Maximum objects inserted per synchronous chunk in replaceScope().
// The first chunk is always processed synchronously (in the same call frame
// as the clear) so consumers never observe an empty pool. Subsequent chunks
// are scheduled via setTimeout(0) to yield to the browser between each batch.
const REPLACE_CHUNK_SIZE = 200

/**
 * A scope is the delivery channel an object came from. Every object in the
 * pool belongs to one or more scopes; clearing a scope removes that scope
 * from each object's set, and only removes the object when its set is empty.
 *
 * This is how cross-scope objects (the user's own member row, which arrives
 * via both the personal channel and a workspace channel) naturally survive
 * a workspace switch: clearing `workspace:A` leaves them in `personal`.
 *
 * Scope is the branded string from `@/api/scope` — kept stringly-equal so
 * it slots into Map/Set keys, but the compiler refuses raw strings at
 * callsites that take a Scope.
 */
/** A removed object plus the set of scopes it was in, so callers can
 *  restore it correctly on rollback. */
export interface RemovedEntry {
  object: PoolObject
  scopes: Scope[]
}

// Generate unique ID for pending updates
let pendingIdCounter = 0
function generatePendingId(): string {
  return `pending_${++pendingIdCounter}_${Date.now()}`
}

// Pool change notification types. Every event that creates or updates data
// carries a `scope` so the persistence layer can route to the right cache
// bucket without re-deriving anything. `remove` carries the set of scopes
// the object was in so the cache can clean up every bucket it occupied.
export interface PoolChangeImport {
  type: 'import'
  scope: Scope
  objects: PoolObject[]
}

export interface PoolChangeSet {
  type: 'set'
  scope: Scope
  object: PoolObject
}

export interface PoolChangeRemove {
  type: 'remove'
  objectType: ObjectType
  id: string
  scopes: Scope[]
}

export interface PoolChangeReplaceScope {
  type: 'replaceScope'
  scope: Scope
  objects: PoolObject[]
}

export interface PoolChangeClearScope {
  type: 'clearScope'
  scope: Scope
}

export type PoolChange =
  | PoolChangeImport
  | PoolChangeSet
  | PoolChangeRemove
  | PoolChangeReplaceScope
  | PoolChangeClearScope

type PoolChangeCallback = (change: PoolChange) => void

const changeCallbacks = new Set<PoolChangeCallback>()

export function onPoolChange(callback: PoolChangeCallback): void {
  changeCallbacks.add(callback)
}

export function offPoolChange(callback: PoolChangeCallback): void {
  changeCallbacks.delete(callback)
}

function notifyChange(change: PoolChange): void {
  for (const callback of changeCallbacks) {
    callback(change)
  }
}

// Create empty storage maps from OBJECT_TYPES
function createEmptyStorage(): Map<ObjectType, Map<string, PoolObject>> {
  return new Map(OBJECT_TYPES.map((type) => [type, new Map()]))
}

// Cascade relationships: parent type → [{ childType, foreignKey }]
const CASCADE_RULES: Partial<
  Record<ObjectType, { childType: ObjectType; foreignKey: string }[]>
> = {
  event: [
    { childType: 'datePoll', foreignKey: 'eventId' },
    { childType: 'rsvp', foreignKey: 'eventId' },
    { childType: 'expense', foreignKey: 'eventId' },
    { childType: 'settlement', foreignKey: 'eventId' },
    { childType: 'choreRoster', foreignKey: 'eventId' },
  ],
  datePoll: [{ childType: 'dateRange', foreignKey: 'datePollId' }],
  dateRange: [{ childType: 'vote', foreignKey: 'dateRangeId' }],
  settlement: [{ childType: 'settlementTransfer', foreignKey: 'settlementId' }],
  choreRoster: [{ childType: 'chore', foreignKey: 'choreRosterId' }],
  chore: [{ childType: 'choreAssignment', foreignKey: 'choreId' }],
  taskList: [{ childType: 'taskItem', foreignKey: 'taskListId' }],
  expense: [{ childType: 'expenseParticipant', foreignKey: 'expenseId' }],
}

// Reverse index for O(1) cascade lookups.
// Structure: Map<"childType:foreignKey", Map<parentId, Set<childId>>>
// One entry per cascade rule. Maintained in sync with the object pool.
type ReverseIndexKey = string // `${childType}:${foreignKey}`
type ReverseIndex = Map<ReverseIndexKey, Map<string, Set<string>>>

// Pre-compute a lookup from childType → rules that reference it (one child
// type can be referenced by at most one parent, but we store as array for
// generality and to match CASCADE_RULES structure).
interface ChildRuleRef {
  childType: ObjectType
  foreignKey: string
  indexKey: ReverseIndexKey
}

const CHILD_RULE_REFS: Partial<Record<ObjectType, ChildRuleRef[]>> = {}
for (const [, rules] of Object.entries(CASCADE_RULES) as [
  ObjectType,
  { childType: ObjectType; foreignKey: string }[],
][]) {
  for (const rule of rules) {
    const ref: ChildRuleRef = {
      childType: rule.childType,
      foreignKey: rule.foreignKey,
      indexKey: `${rule.childType}:${rule.foreignKey}`,
    }
    if (!CHILD_RULE_REFS[rule.childType]) {
      CHILD_RULE_REFS[rule.childType] = []
    }
    CHILD_RULE_REFS[rule.childType]!.push(ref)
  }
}

function createEmptyReverseIndex(): ReverseIndex {
  const index: ReverseIndex = new Map()
  for (const rules of Object.values(CASCADE_RULES) as {
    childType: ObjectType
    foreignKey: string
  }[][]) {
    for (const rule of rules) {
      const key: ReverseIndexKey = `${rule.childType}:${rule.foreignKey}`
      if (!index.has(key)) {
        index.set(key, new Map())
      }
    }
  }
  return index
}

// Add a child object to the reverse index
function reverseIndexAdd(index: ReverseIndex, obj: PoolObject): void {
  const refs = CHILD_RULE_REFS[obj.objectType]
  if (!refs) return
  const raw = obj as unknown as Record<string, unknown>
  for (const ref of refs) {
    const parentId = raw[ref.foreignKey] as string | null | undefined
    if (!parentId) continue
    const parentMap = index.get(ref.indexKey)
    if (!parentMap) continue
    let childSet = parentMap.get(parentId)
    if (!childSet) {
      childSet = new Set()
      parentMap.set(parentId, childSet)
    }
    childSet.add(obj.id)
  }
}

// Remove a child object from the reverse index.
// oldObj is the previous version of the object (needed to get the old FK value).
function reverseIndexRemove(index: ReverseIndex, obj: PoolObject): void {
  const refs = CHILD_RULE_REFS[obj.objectType]
  if (!refs) return
  const raw = obj as unknown as Record<string, unknown>
  for (const ref of refs) {
    const parentId = raw[ref.foreignKey] as string | null | undefined
    if (!parentId) continue
    const parentMap = index.get(ref.indexKey)
    if (!parentMap) continue
    const childSet = parentMap.get(parentId)
    if (childSet) {
      childSet.delete(obj.id)
      if (childSet.size === 0) parentMap.delete(parentId)
    }
  }
}

// Look up child IDs for a given parent in the reverse index
function reverseIndexChildren(
  index: ReverseIndex,
  childType: ObjectType,
  foreignKey: string,
  parentId: string
): Set<string> {
  const key: ReverseIndexKey = `${childType}:${foreignKey}`
  return index.get(key)?.get(parentId) ?? new Set()
}

export type ReadTransform = <T extends ObjectType>(
  type: T,
  obj: ObjectTypeMap[T]
) => ObjectTypeMap[T]

export const useObjectPoolStore = defineStore('objectPool', () => {
  // Storage: Map<ObjectType, Map<id, object>>
  const objects = ref(createEmptyStorage())

  // Reverse index for O(1) cascade lookups: childType:foreignKey → parentId → Set<childId>
  const cascadeIndex = createEmptyReverseIndex()

  // Transform applied to all consumer-facing reads (get/getAll/getMany).
  // No-op by default; will become the decryption layer.
  const readTransform = ref<ReadTransform | null>(null)

  // Tracks how many times setReadTransform has been called so the getAll
  // cache can be invalidated when the transform changes.
  let transformVersion = 0

  function setReadTransform(transform: ReadTransform): void {
    readTransform.value = transform
    transformVersion++
  }

  function applyTransform<T extends ObjectType>(
    type: T,
    obj: ObjectTypeMap[T]
  ): ObjectTypeMap[T] {
    return readTransform.value ? readTransform.value(type, obj) : obj
  }

  // Pending optimistic updates: Map<"type:id", PendingUpdate[]>
  const pendingUpdates = ref(new Map<string, PendingUpdate[]>())

  // Reverse index: pendingId → pendingKey for O(1) lookup in removePending
  const pendingIdToKey = new Map<string, string>()

  // IDs of temp objects inserted via set() whose create commands are still in
  // the command queue (not yet confirmed by the server). Cleared when the
  // server confirms the object via importObjects() or replaceScope(). Used by
  // replaceScope() to distinguish temp objects (which must survive a full
  // sync) from server-confirmed objects that have since been deleted on the
  // server.
  const tempObjectIds = new Set<string>()

  // Ids removed while a chunked replaceScope() is yielding between chunks.
  // remove/removeMany/cascadeRemove feed every in-flight replace's tracker
  // so later chunks don't resurrect an object a delete broadcast (or an
  // optimistic delete) removed mid-replace. Usually empty.
  const replaceRemovalTrackers = new Set<Set<string>>()

  function noteRemovalDuringReplace(id: string): void {
    for (const tracker of replaceRemovalTrackers) {
      tracker.add(id)
    }
  }

  // Tracks which scopes each object currently belongs to. The pool is a
  // multi-scope union: clearing a scope removes that scope from every
  // object's set; the object itself is only removed when its set is empty.
  // This is how the user's own member row (delivered via both the personal
  // channel and a workspace channel) naturally survives a workspace switch.
  //
  // Keyed by object id alone — IDs are UUIDs and globally unique across
  // object types, so no type prefix is needed.
  const objectScopes = new Map<string, Set<Scope>>()

  // Reverse index: which object ids live in each scope. Lets clearScope and
  // replaceScope iterate just the affected scope's objects instead of
  // scanning the entire pool. Kept in sync with objectScopes via the
  // helpers below.
  const scopeToIds = new Map<Scope, Set<string>>()

  function addObjectScope(id: string, scope: Scope): void {
    let set = objectScopes.get(id)
    if (!set) {
      set = new Set()
      objectScopes.set(id, set)
    }
    set.add(scope)
    let idsInScope = scopeToIds.get(scope)
    if (!idsInScope) {
      idsInScope = new Set()
      scopeToIds.set(scope, idsInScope)
    }
    idsInScope.add(id)
  }

  function removeObjectScope(id: string, scope: Scope): void {
    const set = objectScopes.get(id)
    if (set) {
      set.delete(scope)
      if (set.size === 0) objectScopes.delete(id)
    }
    const idsInScope = scopeToIds.get(scope)
    if (idsInScope) {
      idsInScope.delete(id)
      if (idsInScope.size === 0) scopeToIds.delete(scope)
    }
  }

  function dropObjectFromAllScopes(id: string): void {
    const set = objectScopes.get(id)
    if (!set) return
    for (const scope of set) {
      const idsInScope = scopeToIds.get(scope)
      if (idsInScope) {
        idsInScope.delete(id)
        if (idsInScope.size === 0) scopeToIds.delete(scope)
      }
    }
    objectScopes.delete(id)
  }

  function scopesOf(id: string): Scope[] {
    const set = objectScopes.get(id)
    return set ? Array.from(set) : []
  }

  // Per-type version counters to limit reactivity invalidation scope
  const typeVersions = ref(
    new Map<ObjectType, number>(OBJECT_TYPES.map((type) => [type, 0]))
  )

  // Memoization cache for getAll: type → { typeVersion, transformVersion, result }
  // Bounded by the number of object types — no memory leak risk.
  const getAllCache = new Map<
    ObjectType,
    { typeVersion: number; transformVersion: number; result: unknown[] }
  >()

  function bumpVersion(...types: ObjectType[]): void {
    for (const type of types) {
      typeVersions.value.set(type, (typeVersions.value.get(type) ?? 0) + 1)
    }
    triggerRef(typeVersions)
  }

  // Microtask-debounce state for importObjects().
  // When multiple importObjects() calls arrive in the same event loop tick
  // (e.g. during a WebSocket sync burst), we increment version counters eagerly
  // so the final values are correct, but defer all triggerRef() calls until the
  // microtask queue drains. This coalesces N Vue reactivity triggers into one
  // per burst, eliminating redundant recomputation of pool consumers.
  let importTriggerScheduled = false

  function scheduleImportTrigger(): void {
    if (importTriggerScheduled) return
    importTriggerScheduled = true
    queueMicrotask(() => {
      importTriggerScheduled = false
      triggerRef(typeVersions)
      triggerRef(objects)
      triggerRef(pendingUpdates)
    })
  }

  // Return the current version number for a specific type.
  // Reading this inside a computed establishes a scoped reactive dependency:
  // the computed will only re-evaluate when that type's data changes.
  // Use this when you need explicit reactivity without calling getAll/get.
  function getVersion(type: ObjectType): number {
    return typeVersions.value.get(type) ?? 0
  }

  // Derive the scope an object should be inserted into when no scope is
  // explicitly passed. Order:
  //   1. existing scopes of this object id — preserve current membership
  //      (so an update to a notification already in `personal` stays there)
  //   2. `obj.workspaceId` if present — fresh insert into the object's home
  //      workspace, resilient to a workspace switch mid-flight
  //   3. the active workspace — last resort for scope-less objects like
  //      dateRange / vote whose own row doesn't carry workspaceId
  // Throws if none of the above is available — better loud than misrouting.
  function deriveScope(obj: PoolObject): Scope {
    const existing = objectScopes.get(obj.id)
    if (existing && existing.size > 0) {
      return existing.values().next().value as Scope
    }
    const objWsId = (obj as { workspaceId?: string | null }).workspaceId
    if (objWsId) return Scope.workspace(objWsId)
    const wsId = useWorkspaceStore().currentWorkspaceId
    if (!wsId) {
      throw new Error(
        `objectPool: no scope could be derived for ${obj.objectType}:${obj.id} — pass opts.scope, set obj.workspaceId, or ensure a workspace is active`
      )
    }
    return Scope.workspace(wsId)
  }

  // Merge a batch of objects from a delivery channel into the pool. Each
  // object is tagged with a scope — if it's already in the pool from
  // another scope, the scope is added to its set without replacing the
  // object (newer-updatedAt still wins for the actual data).
  //
  // Pass `opts.scope` from sync paths (WebSocket envelope, REST snapshot)
  // where the delivery channel is the authoritative scope. Omit it from
  // optimistic-create paths in stores; the pool will derive a scope from
  // each object via `deriveScope`. Pass `opts.fromCache` from IDB
  // hydration paths — cache re-imports are not server confirmations and
  // must not clear temp marks.
  function importObjects(
    poolObjects: PoolObject[],
    opts?: { scope?: Scope; fromCache?: boolean }
  ): void {
    const explicitScope = opts?.scope
    let changed = false
    // Group imported objects by their resolved scope so we can emit one
    // import change per scope (persistence layer routes per-scope buckets).
    const importedByScope = new Map<Scope, PoolObject[]>()
    for (const obj of poolObjects) {
      const typeMap = objects.value.get(obj.objectType)
      if (!typeMap) continue

      const scope = explicitScope ?? deriveScope(obj)
      const existing = typeMap.get(obj.id)
      const pendingKey = `${obj.objectType}:${obj.id}`
      const hadPending = pendingUpdates.value.has(pendingKey)

      // Clear pending updates only when the server response postdates them.
      // If any pending update was created AFTER the server object's updatedAt,
      // the update represents a newer user action and must be preserved.
      // This prevents a concurrent addItem response (with an older updatedAt)
      // from clearing a completedAt update made after the item was created.
      if (hadPending) {
        const pending = pendingUpdates.value.get(pendingKey)!
        const serverMs = new Date(obj.updatedAt).getTime()
        const hasPendingNewerThanServer = pending.some(
          (u) => u.timestamp > serverMs
        )
        if (!hasPendingNewerThanServer) {
          for (const u of pending) pendingIdToKey.delete(u.id)
          pendingUpdates.value.delete(pendingKey)
          changed = true
        }
      }

      // Server has confirmed this object — it's no longer an unconfirmed
      // temp object. Cache hydration re-imports (startup, workspace
      // switch-back) are not confirmations and keep the mark.
      if (!opts?.fromCache && tempObjectIds.has(obj.id)) {
        tempObjectIds.delete(obj.id)
      }

      addObjectScope(obj.id, scope)

      // Update pool object if newer, doesn't exist, or the incoming copy adds
      // permissions the existing same-version copy lacks (see upgradesPermissions)
      if (
        !existing ||
        isNewer(obj.updatedAt, existing.updatedAt) ||
        upgradesPermissions(obj, existing)
      ) {
        // Update reverse index: remove old FK entry (if any), add new one
        if (existing) reverseIndexRemove(cascadeIndex, existing)
        reverseIndexAdd(cascadeIndex, obj)
        typeMap.set(obj.id, obj)
        const bucket = importedByScope.get(scope) ?? []
        bucket.push(obj)
        importedByScope.set(scope, bucket)
        changed = true
      }
    }
    // Trigger reactivity for nested Map changes — deferred to a microtask so
    // that multiple importObjects() calls within the same event loop tick
    // (e.g. during a WebSocket sync burst) coalesce into a single Vue trigger.
    if (changed) {
      // Increment per-type version counters eagerly so getAll() cache
      // invalidation is correct when the deferred triggerRef() fires.
      for (const objs of importedByScope.values()) {
        for (const obj of objs) {
          typeVersions.value.set(
            obj.objectType,
            (typeVersions.value.get(obj.objectType) ?? 0) + 1
          )
        }
      }
      scheduleImportTrigger()
    }
    for (const [scope, objs] of importedByScope) {
      notifyChange({ type: 'import', scope, objects: objs })
    }
  }

  // Get an object by type and id, with pending updates merged
  function get<T extends ObjectType>(
    type: T,
    id: string
  ): ObjectTypeMap[T] | undefined {
    // Access per-type version to establish scoped reactivity dependency
    void typeVersions.value.get(type)

    const typeMap = objects.value.get(type)
    if (!typeMap) return undefined

    const server = typeMap.get(id) as ObjectTypeMap[T] | undefined
    if (!server) return undefined

    const pendingKey = `${type}:${id}`
    const pending = pendingUpdates.value.get(pendingKey)
    if (!pending?.length) return applyTransform(type, server)

    // Merge all pending changes onto the server data
    const merged = pending.reduce(
      (acc, update) => ({ ...acc, ...update.changes }),
      { ...server }
    )
    return applyTransform(type, merged)
  }

  // Get raw server object without pending updates.
  // Returns a plain (non-reactive) object so it can be safely stored in IndexedDB.
  function getServer<T extends ObjectType>(
    type: T,
    id: string
  ): ObjectTypeMap[T] | undefined {
    const typeMap = objects.value.get(type)
    const obj = typeMap?.get(id)
    return obj ? (toRaw(obj) as ObjectTypeMap[T]) : undefined
  }

  // Get all objects of a type
  // Results are memoized by type version + transform version to avoid
  // materializing intermediate arrays and objects on every call.
  function getAll<T extends ObjectType>(type: T): ObjectTypeMap[T][] {
    // Access per-type version to establish scoped reactivity dependency
    const currentTypeVersion = typeVersions.value.get(type) ?? 0

    const cached = getAllCache.get(type)
    if (
      cached !== undefined &&
      cached.typeVersion === currentTypeVersion &&
      cached.transformVersion === transformVersion
    ) {
      return cached.result as ObjectTypeMap[T][]
    }

    const typeMap = objects.value.get(type)
    if (!typeMap) return []

    const result = Array.from(typeMap.values()).map((obj) => {
      const pendingKey = `${type}:${obj.id}`
      const pending = pendingUpdates.value.get(pendingKey)
      if (!pending?.length) return applyTransform(type, obj as ObjectTypeMap[T])

      const merged = pending.reduce<Record<string, unknown>>(
        (acc, update) => ({ ...acc, ...update.changes }),
        { ...obj }
      ) as unknown as ObjectTypeMap[T]
      return applyTransform(type, merged)
    })

    getAllCache.set(type, {
      typeVersion: currentTypeVersion,
      transformVersion,
      result,
    })

    return result
  }

  // Find a single object by a field value (e.g. member by userId)
  function findBy<T extends ObjectType>(
    type: T,
    field: string,
    value: unknown
  ): ObjectTypeMap[T] | undefined {
    return getAll(type).find(
      (obj) => (obj as unknown as Record<string, unknown>)[field] === value
    )
  }

  // Get multiple objects by IDs
  function getMany<T extends ObjectType>(
    type: T,
    ids: string[]
  ): ObjectTypeMap[T][] {
    return ids
      .map((id) => get(type, id))
      .filter((obj): obj is ObjectTypeMap[T] => obj !== undefined)
  }

  // Add a pending optimistic update
  function addPending<T extends ObjectType>(
    objectType: T,
    objectId: string,
    changes: Partial<ObjectTypeMap[T]>
  ): string {
    const pendingId = generatePendingId()
    const pendingKey = `${objectType}:${objectId}`

    const update: PendingUpdate<T> = {
      id: pendingId,
      objectType,
      objectId,
      changes,
      timestamp: Date.now(),
    }

    const existing = pendingUpdates.value.get(pendingKey) || []
    pendingUpdates.value.set(pendingKey, [...existing, update as PendingUpdate])
    pendingIdToKey.set(pendingId, pendingKey)
    bumpVersion(objectType)
    triggerRef(pendingUpdates)

    return pendingId
  }

  // Remove a specific pending update (for rollback)
  function removePending(pendingId: string): void {
    const key = pendingIdToKey.get(pendingId)
    if (!key) return

    pendingIdToKey.delete(pendingId)

    const updates = pendingUpdates.value.get(key)
    if (!updates) return

    const filtered = updates.filter((u) => u.id !== pendingId)
    if (filtered.length === 0) {
      pendingUpdates.value.delete(key)
    } else {
      pendingUpdates.value.set(key, filtered)
    }

    bumpVersion(key.split(':')[0] as ObjectType)
    triggerRef(pendingUpdates)
  }

  // Check if an object has pending updates
  function hasPending(objectType: ObjectType, objectId: string): boolean {
    const pendingKey = `${objectType}:${objectId}`
    const pending = pendingUpdates.value.get(pendingKey)
    return Boolean(pending && pending.length > 0)
  }

  // Set an object directly. Scope resolution mirrors `importObjects`:
  // opts.scope from sync paths overrides; otherwise the pool keeps the
  // object in whatever scopes it already lives in (so marking a personal-
  // scope notification read doesn't move it), and falls back to deriving a
  // fresh scope from `obj.workspaceId` or the active workspace.
  //
  // Pass `isTemp: true` when the object is an optimistic placeholder for a
  // create command still in the queue. This records the ID in tempObjectIds
  // so replaceScope() can preserve the object during a full sync.
  //
  // Do NOT pass isTemp for rollback restores — those are server-confirmed
  // objects being put back after a failed delete and must not be preserved
  // beyond the next authoritative full sync. Rollback callers should use
  // `restore(removedEntries)` rather than calling `set` per scope.
  function set<T extends ObjectType>(
    object: ObjectTypeMap[T],
    opts?: { scope?: Scope; isTemp?: boolean }
  ): void {
    const typeMap = objects.value.get(object.objectType)
    if (!typeMap) return
    const existing = typeMap.get(object.id)
    if (existing) reverseIndexRemove(cascadeIndex, existing)
    reverseIndexAdd(cascadeIndex, object)
    typeMap.set(object.id, object)
    if (opts?.isTemp) tempObjectIds.add(object.id)

    // Resolve target scopes: explicit beats existing beats derivation.
    let scopes: Scope[]
    if (opts?.scope) {
      addObjectScope(object.id, opts.scope)
      scopes = [opts.scope]
    } else {
      const existingScopes = objectScopes.get(object.id)
      if (existingScopes && existingScopes.size > 0) {
        scopes = Array.from(existingScopes)
      } else {
        const derived = deriveScope(object)
        addObjectScope(object.id, derived)
        scopes = [derived]
      }
    }

    bumpVersion(object.objectType)
    triggerRef(objects)
    // Emit one event per scope so persistence routes to every IDB bucket
    // the object belongs to. For the common single-scope case this is just
    // one event; for a multi-scope object (own member row) an update fans
    // out to both buckets without callers having to loop.
    for (const scope of scopes) {
      notifyChange({ type: 'set', scope, object })
    }
  }

  // Mark an object id as an unconfirmed optimistic create so replaceScope
  // preserves it. Used on startup: tempObjectIds is in-memory, so a queued
  // create's object hydrated from the cache would otherwise be dropped by
  // the next full sync while its command is still waiting to replay.
  function markTemp(objectId: string): void {
    tempObjectIds.add(objectId)
  }

  // Restore a batch of previously-removed entries to the pool. Each entry
  // re-enters every scope it came from (carried on RemovedEntry), so a
  // rollback for a multi-scope object restores it to every channel it
  // was on. Pool persistence is updated once per (entry, scope) pair.
  //
  // Entries can be stale: a queued delete's snapshot may be rolled back
  // hours later (or after a restart), by which time the server may have
  // re-delivered a newer copy. Same-or-newer existing copies win.
  function restore(entries: RemovedEntry[]): void {
    for (const entry of entries) {
      const existing = objects.value
        .get(entry.object.objectType)
        ?.get(entry.object.id)
      if (existing && !isNewer(entry.object.updatedAt, existing.updatedAt)) {
        continue
      }
      const scopes =
        entry.scopes.length > 0 ? entry.scopes : [deriveScope(entry.object)]
      for (const scope of scopes) {
        set(entry.object, { scope })
      }
    }
  }

  // Remove an object from the pool across all scopes it belonged to.
  // The emitted change carries those scopes so persistence can clean up
  // every IDB bucket the object lived in.
  function remove(objectType: ObjectType, objectId: string): void {
    noteRemovalDuringReplace(objectId)
    const scopes = scopesOf(objectId)
    const typeMap = objects.value.get(objectType)
    if (typeMap) {
      const existing = typeMap.get(objectId)
      if (existing) reverseIndexRemove(cascadeIndex, existing)
      typeMap.delete(objectId)
    }
    dropObjectFromAllScopes(objectId)
    // Also clear any pending updates and temp tracking
    const removedKey = `${objectType}:${objectId}`
    const removedPending = pendingUpdates.value.get(removedKey)
    if (removedPending) {
      for (const u of removedPending) pendingIdToKey.delete(u.id)
    }
    pendingUpdates.value.delete(removedKey)
    tempObjectIds.delete(objectId)
    bumpVersion(objectType)
    triggerRef(objects)
    triggerRef(pendingUpdates)
    notifyChange({ type: 'remove', objectType, id: objectId, scopes })
  }

  // Batch remove: removes multiple objects of the same type with a single
  // reactivity trigger instead of one per object.
  function removeMany(objectType: ObjectType, objectIds: string[]): void {
    const typeMap = objects.value.get(objectType)
    const removedScopes = new Map<string, Scope[]>()
    for (const objectId of objectIds) {
      noteRemovalDuringReplace(objectId)
      removedScopes.set(objectId, scopesOf(objectId))
      if (typeMap) {
        const existing = typeMap.get(objectId)
        if (existing) reverseIndexRemove(cascadeIndex, existing)
        typeMap.delete(objectId)
      }
      dropObjectFromAllScopes(objectId)
      const removedKey = `${objectType}:${objectId}`
      const removedPending = pendingUpdates.value.get(removedKey)
      if (removedPending) {
        for (const u of removedPending) pendingIdToKey.delete(u.id)
      }
      pendingUpdates.value.delete(removedKey)
      tempObjectIds.delete(objectId)
    }
    if (objectIds.length > 0) {
      bumpVersion(objectType)
      triggerRef(objects)
      triggerRef(pendingUpdates)
      for (const id of objectIds) {
        notifyChange({
          type: 'remove',
          objectType,
          id,
          scopes: removedScopes.get(id) ?? [],
        })
      }
    }
  }

  // Cascade-remove an object and all its children, returning every removed
  // entry (object + its prior scope set). Rollback callers thread those
  // scopes back into pool.set() so the restored objects re-enter the same
  // channels they came from.
  function cascadeRemove(
    objectType: ObjectType,
    objectId: string
  ): RemovedEntry[] {
    const removed: RemovedEntry[] = []
    const typesChanged = new Set<ObjectType>()

    function removeRecursive(type: ObjectType, id: string): void {
      // Track even when the object isn't in the pool (yet): a delete
      // broadcast can land before a chunked replace inserts the object.
      noteRemovalDuringReplace(id)
      const typeMap = objects.value.get(type)
      if (!typeMap) return

      const obj = typeMap.get(id)
      if (obj) {
        // toRaw because removed entries are persisted (rollback linkage in
        // commandDb) and IDB structured-clones them — reactive proxies
        // aren't cloneable.
        removed.push({ object: toRaw(obj), scopes: scopesOf(id) })
        reverseIndexRemove(cascadeIndex, obj)
        typeMap.delete(id)
        dropObjectFromAllScopes(id)
        const cascadeKey = `${type}:${id}`
        const cascadePending = pendingUpdates.value.get(cascadeKey)
        if (cascadePending) {
          for (const u of cascadePending) pendingIdToKey.delete(u.id)
        }
        pendingUpdates.value.delete(cascadeKey)
        tempObjectIds.delete(id)
        typesChanged.add(type)
      }

      // Find and remove children using the reverse index for O(1) lookups
      const rules = CASCADE_RULES[type]
      if (!rules) return

      for (const rule of rules) {
        // Snapshot child IDs before iterating — removeRecursive modifies the index
        const childIds = Array.from(
          reverseIndexChildren(
            cascadeIndex,
            rule.childType,
            rule.foreignKey,
            id
          )
        )
        for (const childId of childIds) {
          removeRecursive(rule.childType, childId)
        }
      }
    }

    removeRecursive(objectType, objectId)

    if (typesChanged.size > 0) {
      bumpVersion(...typesChanged)
      triggerRef(objects)
      triggerRef(pendingUpdates)
      for (const entry of removed) {
        notifyChange({
          type: 'remove',
          objectType: entry.object.objectType,
          id: entry.object.id,
          scopes: entry.scopes,
        })
      }
    }

    return removed
  }

  // Computed to get pool stats (useful for debugging)
  const stats = computed(() => {
    const result = {} as Record<ObjectType, number>
    for (const type of OBJECT_TYPES) {
      result[type] = objects.value.get(type)?.size ?? 0
    }
    return result
  })

  // Remove `scope` from every object that carries it. Objects that also
  // belong to another scope stay in the pool with their remaining scope
  // set; objects whose only scope was this one are dropped. Used during a
  // workspace switch: clearing `workspace:<previous>` keeps personally-
  // scoped data (the workspace selector, own memberships, notifications)
  // in place because those objects also live in `personal`.
  function clearScope(scope: Scope): void {
    const changedTypes = new Set<ObjectType>()
    const idsInScope = scopeToIds.get(scope)
    if (idsInScope) {
      // Snapshot because removeObjectScope/dropObjectFromAllScopes mutate
      // scopeToIds underneath us.
      for (const id of Array.from(idsInScope)) {
        const scopes = objectScopes.get(id)
        if (!scopes) continue
        if (scopes.size > 1) {
          // Object also lives in another scope — strip just this one.
          removeObjectScope(id, scope)
          continue
        }
        // Last scope — fully remove the object.
        dropObjectFromAllScopes(id)
        tempObjectIds.delete(id)
        for (const [type, typeMap] of objects.value) {
          const existing = typeMap.get(id)
          if (existing) {
            reverseIndexRemove(cascadeIndex, existing)
            typeMap.delete(id)
            changedTypes.add(type)
            // We know the type, so build the exact pending key directly
            // instead of scanning every key for a suffix match.
            clearPendingFor(type, id)
            break
          }
        }
      }
    }
    if (changedTypes.size > 0) {
      bumpVersion(...changedTypes)
      triggerRef(objects)
      triggerRef(pendingUpdates)
    }
    notifyChange({ type: 'clearScope', scope })
  }

  function clearPendingFor(type: ObjectType, id: string): void {
    const key = `${type}:${id}`
    const updates = pendingUpdates.value.get(key)
    if (!updates) return
    for (const u of updates) pendingIdToKey.delete(u.id)
    pendingUpdates.value.delete(key)
  }

  // Replace one scope's objects with the server's authoritative set.
  // Preserves pending updates that are newer than the server data (queued
  // commands), and temp objects in this scope that aren't yet in the server
  // payload (their create commands are still queued).
  //
  // Objects are inserted in chunks of REPLACE_CHUNK_SIZE. The clear and the
  // first chunk run in the same synchronous call frame so consumers never
  // observe an empty pool. Subsequent chunks yield via setTimeout(0).
  function replaceScope(
    scope: Scope,
    poolObjects: PoolObject[]
  ): Promise<void> {
    const serverIds = new Set<string>()
    for (const obj of poolObjects) {
      serverIds.add(obj.id)
    }

    // Build index of incoming server timestamps for pending-update comparison
    const serverTimestamps = new Map<string, number>()
    for (const obj of poolObjects) {
      serverTimestamps.set(
        `${obj.objectType}:${obj.id}`,
        new Date(obj.updatedAt).getTime()
      )
    }

    // Preserve pending updates that postdate the server data
    for (const [key, updates] of pendingUpdates.value) {
      const serverMs = serverTimestamps.get(key) ?? 0
      const newer = updates.filter((u) => u.timestamp > serverMs)
      const stale = updates.filter((u) => u.timestamp <= serverMs)
      for (const u of stale) pendingIdToKey.delete(u.id)
      if (newer.length === 0) {
        pendingUpdates.value.delete(key)
      } else {
        pendingUpdates.value.set(key, newer)
      }
    }

    // Snapshot temp objects in this scope that aren't in the server payload —
    // their create commands are still queued and the object must survive.
    // Temp objects confirmed by the server drop their temp flag.
    const idsInScope = scopeToIds.get(scope)
    const tempObjectsToPreserve: PoolObject[] = []
    for (const id of Array.from(tempObjectIds)) {
      if (serverIds.has(id)) {
        tempObjectIds.delete(id)
        continue
      }
      if (!idsInScope?.has(id)) continue
      for (const typeMap of objects.value.values()) {
        const obj = typeMap.get(id)
        if (obj) {
          tempObjectsToPreserve.push(obj)
          break
        }
      }
    }

    // Remove `scope` from every object that carries it. Multi-scope objects
    // (e.g. own member row in both `personal` and `workspace:A`) stay; only
    // scope-only objects are dropped from the pool entirely. When an object
    // is dropped, drop any pending updates keyed to it too — otherwise they
    // would linger orphaned in pendingUpdates with no server object to
    // overlay, and resurrect if the same id reappeared.
    const changedTypes = new Set<ObjectType>()
    if (idsInScope) {
      // Snapshot because removeObjectScope/dropObjectFromAllScopes mutate
      // scopeToIds underneath us.
      for (const id of Array.from(idsInScope)) {
        const scopes = objectScopes.get(id)
        if (!scopes) continue
        if (scopes.size > 1) {
          removeObjectScope(id, scope)
          continue
        }
        dropObjectFromAllScopes(id)
        for (const [type, typeMap] of objects.value) {
          const existing = typeMap.get(id)
          if (existing) {
            reverseIndexRemove(cascadeIndex, existing)
            typeMap.delete(id)
            changedTypes.add(type)
            // Only drop pending overlays for objects that aren't coming back
            // in this replay — objects that will be re-inserted below keep
            // their (newer-than-server) pending updates from the reconcile
            // pass above.
            if (!serverIds.has(id)) clearPendingFor(type, id)
            break
          }
        }
      }
    }

    // All objects to insert: server data (under `scope`) + preserved temps
    // (re-tagged with `scope` since they were already in this scope).
    const allObjects: PoolObject[] = [...poolObjects, ...tempObjectsToPreserve]

    // Ids removed while this replace is in flight — later chunks skip them
    // so a delete that lands between chunks isn't resurrected.
    const removedDuringReplace = new Set<string>()

    // Insert one payload object. The pool isn't frozen during a replace: a
    // broadcast can merge a newer copy before this object's chunk runs, and
    // multi-scope objects survive the clear above. Apply the same rule as
    // importObjects — newer updatedAt wins, and a same-version copy still
    // wins when it adds viewer permissions. Scope membership is recorded
    // either way: the object is in this scope per the server.
    function insertFromPayload(obj: PoolObject): void {
      if (removedDuringReplace.has(obj.id)) return
      const typeMap = objects.value.get(obj.objectType)
      if (!typeMap) return
      const existing = typeMap.get(obj.id)
      if (
        !existing ||
        isNewer(obj.updatedAt, existing.updatedAt) ||
        upgradesPermissions(obj, existing)
      ) {
        if (existing) reverseIndexRemove(cascadeIndex, existing)
        reverseIndexAdd(cascadeIndex, obj)
        typeMap.set(obj.id, obj)
        changedTypes.add(obj.objectType)
      }
      addObjectScope(obj.id, scope)
    }

    const firstChunk = allObjects.slice(0, REPLACE_CHUNK_SIZE)
    for (const obj of firstChunk) {
      insertFromPayload(obj)
    }

    if (allObjects.length <= REPLACE_CHUNK_SIZE) {
      if (changedTypes.size > 0) bumpVersion(...changedTypes)
      triggerRef(objects)
      triggerRef(pendingUpdates)
      notifyChange({ type: 'replaceScope', scope, objects: poolObjects })
      return Promise.resolve()
    }

    replaceRemovalTrackers.add(removedDuringReplace)

    return new Promise<void>((resolve) => {
      let offset = REPLACE_CHUNK_SIZE

      function processNextChunk(): void {
        const chunk = allObjects.slice(offset, offset + REPLACE_CHUNK_SIZE)
        offset += REPLACE_CHUNK_SIZE

        for (const obj of chunk) {
          insertFromPayload(obj)
        }

        if (offset < allObjects.length) {
          setTimeout(processNextChunk, 0)
        } else {
          replaceRemovalTrackers.delete(removedDuringReplace)
          if (changedTypes.size > 0) bumpVersion(...changedTypes)
          triggerRef(objects)
          triggerRef(pendingUpdates)
          notifyChange({ type: 'replaceScope', scope, objects: poolObjects })
          resolve()
        }
      }

      setTimeout(processNextChunk, 0)
    })
  }

  /**
   * Single entry point for "the server sent us a batch of changes for this
   * scope, merge them into the pool." Dispatches to replaceScope for full
   * syncs and importObjects + cascadeRemove for incremental merges.
   */
  function applyUpdate(scope: Scope, update: PoolUpdate): void {
    if (update.kind === 'replace') {
      // replaceScope returns a Promise but its async work (chunked rebuild)
      // is fire-and-forget at the WebSocket level today.
      void replaceScope(scope, update.objects)
      return
    }
    if (update.objects?.length) {
      importObjects(update.objects, { scope })
    }
    if (update.deleted?.length) {
      for (const ref of update.deleted) {
        cascadeRemove(ref.objectType, ref.id)
      }
    }
  }

  // Restore pending updates from cache (used on startup)
  function restorePendingUpdates(cached: Map<string, PendingUpdate[]>): void {
    if (cached.size === 0) return
    const restoredTypes = new Set<ObjectType>()
    for (const [key, updates] of cached) {
      pendingUpdates.value.set(key, updates)
      for (const u of updates) pendingIdToKey.set(u.id, key)
      restoredTypes.add(key.split(':')[0] as ObjectType)
    }
    bumpVersion(...restoredTypes)
    triggerRef(pendingUpdates)
  }

  // Reset the store
  function $reset(): void {
    objects.value = createEmptyStorage()
    pendingUpdates.value = new Map()
    pendingIdToKey.clear()
    tempObjectIds.clear()
    objectScopes.clear()
    scopeToIds.clear()
    getAllCache.clear()
    replaceRemovalTrackers.clear()
    for (const parentMap of cascadeIndex.values()) {
      parentMap.clear()
    }
  }

  return {
    // State
    objects,
    pendingUpdates,
    typeVersions,
    stats,

    // Methods
    getVersion,
    importObjects,
    get,
    getServer,
    getAll,
    findBy,
    getMany,
    addPending,
    removePending,
    hasPending,
    set,
    markTemp,
    restore,
    remove,
    removeMany,
    cascadeRemove,
    replaceScope,
    clearScope,
    applyUpdate,
    restorePendingUpdates,
    setReadTransform,
    scopesOf,
    $reset,
  }
})
