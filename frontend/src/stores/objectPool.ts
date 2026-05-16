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

// Helper to compare ISO8601 timestamps
// ISO 8601 strings with the same format are lexicographically sortable
function isNewer(a: string, b: string): boolean {
  return a > b
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
 */
export type Scope = string

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

  // Tracks which scopes each object currently belongs to. The pool is a
  // multi-scope union: clearing a scope removes that scope from every
  // object's set; the object itself is only removed when its set is empty.
  // This is how the user's own member row (delivered via both the personal
  // channel and a workspace channel) naturally survives a workspace switch.
  const objectScopes = new Map<string, Set<Scope>>()

  function addObjectScope(id: string, scope: Scope): void {
    let set = objectScopes.get(id)
    if (!set) {
      set = new Set()
      objectScopes.set(id, set)
    }
    set.add(scope)
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

  // Merge a batch of objects from a delivery channel into the pool. Each
  // object is tagged with `scope` — if it's already in the pool from
  // another scope, the scope is added to its set without replacing the
  // object (newer-updatedAt still wins for the actual data).
  function importObjects(scope: Scope, poolObjects: PoolObject[]): void {
    let changed = false
    const imported: PoolObject[] = []
    for (const obj of poolObjects) {
      const typeMap = objects.value.get(obj.objectType)
      if (!typeMap) continue

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

      // Server has confirmed this object — it's no longer an unconfirmed temp object
      if (tempObjectIds.has(obj.id)) {
        tempObjectIds.delete(obj.id)
      }

      addObjectScope(obj.id, scope)

      // Update pool object if newer or doesn't exist
      if (!existing || isNewer(obj.updatedAt, existing.updatedAt)) {
        // Update reverse index: remove old FK entry (if any), add new one
        if (existing) reverseIndexRemove(cascadeIndex, existing)
        reverseIndexAdd(cascadeIndex, obj)
        typeMap.set(obj.id, obj)
        imported.push(obj)
        changed = true
      }
    }
    // Trigger reactivity for nested Map changes — deferred to a microtask so
    // that multiple importObjects() calls within the same event loop tick
    // (e.g. during a WebSocket sync burst) coalesce into a single Vue trigger.
    if (changed) {
      // Increment per-type version counters eagerly so getAll() cache
      // invalidation is correct when the deferred triggerRef() fires.
      for (const obj of imported) {
        typeVersions.value.set(
          obj.objectType,
          (typeVersions.value.get(obj.objectType) ?? 0) + 1
        )
      }
      scheduleImportTrigger()
    }
    if (imported.length > 0) {
      notifyChange({ type: 'import', scope, objects: imported })
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

  // Set an object directly. `scope` is the channel this object belongs to —
  // for optimistic creates that's the workspace the user was in; for
  // rollback restores, it's the scope the object came from before removal
  // (callers thread it back through from cascadeRemove's return value).
  //
  // Pass `isTemp: true` when the object is an optimistic placeholder for a
  // create command still in the queue. This records the ID in tempObjectIds
  // so replaceScope() can preserve the object during a full sync.
  //
  // Do NOT pass isTemp for rollback restores — those are server-confirmed
  // objects being put back after a failed delete and must not be preserved
  // beyond the next authoritative full sync.
  function set<T extends ObjectType>(
    scope: Scope,
    object: ObjectTypeMap[T],
    { isTemp = false }: { isTemp?: boolean } = {}
  ): void {
    const typeMap = objects.value.get(object.objectType)
    if (typeMap) {
      const existing = typeMap.get(object.id)
      if (existing) reverseIndexRemove(cascadeIndex, existing)
      reverseIndexAdd(cascadeIndex, object)
      typeMap.set(object.id, object)
      addObjectScope(object.id, scope)
      if (isTemp) {
        tempObjectIds.add(object.id)
      }
      bumpVersion(object.objectType)
      triggerRef(objects)
      notifyChange({ type: 'set', scope, object })
    }
  }

  // Remove an object from the pool across all scopes it belonged to.
  // The emitted change carries those scopes so persistence can clean up
  // every IDB bucket the object lived in.
  function remove(objectType: ObjectType, objectId: string): void {
    const scopes = scopesOf(objectId)
    const typeMap = objects.value.get(objectType)
    if (typeMap) {
      const existing = typeMap.get(objectId)
      if (existing) reverseIndexRemove(cascadeIndex, existing)
      typeMap.delete(objectId)
    }
    objectScopes.delete(objectId)
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
      removedScopes.set(objectId, scopesOf(objectId))
      if (typeMap) {
        const existing = typeMap.get(objectId)
        if (existing) reverseIndexRemove(cascadeIndex, existing)
        typeMap.delete(objectId)
      }
      objectScopes.delete(objectId)
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
      const typeMap = objects.value.get(type)
      if (!typeMap) return

      const obj = typeMap.get(id)
      if (obj) {
        removed.push({ object: obj, scopes: scopesOf(id) })
        reverseIndexRemove(cascadeIndex, obj)
        typeMap.delete(id)
        objectScopes.delete(id)
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
    for (const [id, scopes] of objectScopes) {
      if (!scopes.has(scope)) continue
      scopes.delete(scope)
      if (scopes.size > 0) continue
      // Last scope — fully remove the object.
      objectScopes.delete(id)
      tempObjectIds.delete(id)
      for (const [type, typeMap] of objects.value) {
        const existing = typeMap.get(id)
        if (existing) {
          reverseIndexRemove(cascadeIndex, existing)
          typeMap.delete(id)
          changedTypes.add(type)
          break
        }
      }
      const pendingKey = Array.from(pendingUpdates.value.keys()).find(
        (k) => k.endsWith(`:${id}`)
      )
      if (pendingKey) {
        const updates = pendingUpdates.value.get(pendingKey)
        if (updates) for (const u of updates) pendingIdToKey.delete(u.id)
        pendingUpdates.value.delete(pendingKey)
      }
    }
    if (changedTypes.size > 0) {
      bumpVersion(...changedTypes)
      triggerRef(objects)
      triggerRef(pendingUpdates)
    }
    notifyChange({ type: 'clearScope', scope })
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
    const tempObjectsToPreserve: PoolObject[] = []
    for (const id of Array.from(tempObjectIds)) {
      if (serverIds.has(id)) {
        tempObjectIds.delete(id)
        continue
      }
      if (!objectScopes.get(id)?.has(scope)) continue
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
    // scope-only objects are dropped from the pool entirely.
    const changedTypes = new Set<ObjectType>()
    for (const [id, scopes] of objectScopes) {
      if (!scopes.has(scope)) continue
      scopes.delete(scope)
      if (scopes.size > 0) continue
      objectScopes.delete(id)
      for (const [type, typeMap] of objects.value) {
        const existing = typeMap.get(id)
        if (existing) {
          reverseIndexRemove(cascadeIndex, existing)
          typeMap.delete(id)
          changedTypes.add(type)
          break
        }
      }
    }

    // All objects to insert: server data (under `scope`) + preserved temps
    // (re-tagged with `scope` since they were already in this scope).
    const allObjects: PoolObject[] = [...poolObjects, ...tempObjectsToPreserve]

    const firstChunk = allObjects.slice(0, REPLACE_CHUNK_SIZE)
    for (const obj of firstChunk) {
      const typeMap = objects.value.get(obj.objectType)
      if (typeMap) {
        const existing = typeMap.get(obj.id)
        if (existing) reverseIndexRemove(cascadeIndex, existing)
        reverseIndexAdd(cascadeIndex, obj)
        typeMap.set(obj.id, obj)
        addObjectScope(obj.id, scope)
        changedTypes.add(obj.objectType)
      }
    }

    if (allObjects.length <= REPLACE_CHUNK_SIZE) {
      if (changedTypes.size > 0) bumpVersion(...changedTypes)
      triggerRef(objects)
      triggerRef(pendingUpdates)
      notifyChange({ type: 'replaceScope', scope, objects: poolObjects })
      return Promise.resolve()
    }

    return new Promise<void>((resolve) => {
      let offset = REPLACE_CHUNK_SIZE

      function processNextChunk(): void {
        const chunk = allObjects.slice(offset, offset + REPLACE_CHUNK_SIZE)
        offset += REPLACE_CHUNK_SIZE

        for (const obj of chunk) {
          const typeMap = objects.value.get(obj.objectType)
          if (typeMap) {
            const existing = typeMap.get(obj.id)
            if (existing) reverseIndexRemove(cascadeIndex, existing)
            reverseIndexAdd(cascadeIndex, obj)
            typeMap.set(obj.id, obj)
            addObjectScope(obj.id, scope)
            changedTypes.add(obj.objectType)
          }
        }

        if (offset < allObjects.length) {
          setTimeout(processNextChunk, 0)
        } else {
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
      importObjects(scope, update.objects)
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
    getAllCache.clear()
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
