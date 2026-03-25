import { ref, computed, triggerRef, toRaw } from 'vue'
import { defineStore } from 'pinia'
import {
  OBJECT_TYPES,
  type ObjectType,
  type ObjectTypeMap,
  type PoolObject,
  type PendingUpdate,
} from '@/types/pool'

// Helper to compare ISO8601 timestamps
// ISO 8601 strings with the same format are lexicographically sortable
function isNewer(a: string, b: string): boolean {
  return a > b
}

// Maximum objects inserted per synchronous chunk in replaceObjects().
// The first chunk is always processed synchronously (in the same call frame as
// the clear) so consumers never observe an empty pool. Subsequent chunks are
// scheduled via setTimeout(0) to yield to the browser between each batch.
const REPLACE_CHUNK_SIZE = 500

// Generate unique ID for pending updates
let pendingIdCounter = 0
function generatePendingId(): string {
  return `pending_${++pendingIdCounter}_${Date.now()}`
}

// Pool change notification types
export interface PoolChangeImport {
  type: 'import'
  objects: PoolObject[]
}

export interface PoolChangeSet {
  type: 'set'
  object: PoolObject
}

export interface PoolChangeRemove {
  type: 'remove'
  objectType: ObjectType
  id: string
}

export interface PoolChangeReplace {
  type: 'replace'
  objects: PoolObject[]
}

export type PoolChange =
  | PoolChangeImport
  | PoolChangeSet
  | PoolChangeRemove
  | PoolChangeReplace

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

export type ReadTransform = <T extends ObjectType>(
  type: T,
  obj: ObjectTypeMap[T]
) => ObjectTypeMap[T]

export const useObjectPoolStore = defineStore('objectPool', () => {
  // Storage: Map<ObjectType, Map<id, object>>
  const objects = ref(createEmptyStorage())

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
  // the command queue (not yet confirmed by the server). Cleared when the server
  // confirms the object via importObjects() or replaceObjects(). Used by
  // replaceObjects() to distinguish temp objects (which must survive a full sync)
  // from server-confirmed objects that have since been deleted on the server.
  const tempObjectIds = new Set<string>()

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

  // Import objects from API response - no parsing needed
  function importObjects(poolObjects: PoolObject[]): void {
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

      // Update pool object if newer or doesn't exist
      if (!existing || isNewer(obj.updatedAt, existing.updatedAt)) {
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
      notifyChange({ type: 'import', objects: imported })
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

  // Set an object directly.
  //
  // Pass `isTemp: true` when the object is an optimistic placeholder for a
  // create command still in the queue. This records the ID in tempObjectIds
  // so replaceObjects() can preserve the object during a full sync.
  //
  // Do NOT pass isTemp for rollback restores — those are server-confirmed
  // objects being put back after a failed delete and must not be preserved
  // beyond the next authoritative full sync.
  function set<T extends ObjectType>(
    object: ObjectTypeMap[T],
    { isTemp = false }: { isTemp?: boolean } = {}
  ): void {
    const typeMap = objects.value.get(object.objectType)
    if (typeMap) {
      typeMap.set(object.id, object)
      if (isTemp) {
        tempObjectIds.add(object.id)
      }
      bumpVersion(object.objectType)
      triggerRef(objects)
      notifyChange({ type: 'set', object })
    }
  }

  // Remove an object from the pool
  function remove(objectType: ObjectType, objectId: string): void {
    const typeMap = objects.value.get(objectType)
    if (typeMap) {
      typeMap.delete(objectId)
    }
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
    notifyChange({ type: 'remove', objectType, id: objectId })
  }

  // Cascade-remove an object and all its children, returning all removed objects for rollback
  function cascadeRemove(
    objectType: ObjectType,
    objectId: string
  ): PoolObject[] {
    const removed: PoolObject[] = []
    const typesChanged = new Set<ObjectType>()

    function removeRecursive(type: ObjectType, id: string): void {
      const typeMap = objects.value.get(type)
      if (!typeMap) return

      const obj = typeMap.get(id)
      if (obj) {
        removed.push(obj)
        typeMap.delete(id)
        const cascadeKey = `${type}:${id}`
        const cascadePending = pendingUpdates.value.get(cascadeKey)
        if (cascadePending) {
          for (const u of cascadePending) pendingIdToKey.delete(u.id)
        }
        pendingUpdates.value.delete(cascadeKey)
        tempObjectIds.delete(id)
        typesChanged.add(type)
      }

      // Find and remove children
      const rules = CASCADE_RULES[type]
      if (!rules) return

      for (const rule of rules) {
        const childMap = objects.value.get(rule.childType)
        if (!childMap) continue

        for (const [childId, child] of childMap) {
          if (
            (child as unknown as Record<string, unknown>)[rule.foreignKey] ===
            id
          ) {
            removeRecursive(rule.childType, childId)
          }
        }
      }
    }

    removeRecursive(objectType, objectId)

    if (typesChanged.size > 0) {
      bumpVersion(...typesChanged)
      triggerRef(objects)
      triggerRef(pendingUpdates)
      notifyChange({ type: 'remove', objectType, id: objectId })
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

  // Clear all object types except specified ones (used during workspace switch)
  function clearExcept(...keepTypes: ObjectType[]): void {
    const keepSet = new Set(keepTypes)
    const clearedTypes: ObjectType[] = []
    for (const type of OBJECT_TYPES) {
      if (!keepSet.has(type)) {
        objects.value.get(type)?.clear()
        clearedTypes.push(type)
      }
    }
    // Clear pending updates and temp tracking for cleared types
    for (const [key, updates] of pendingUpdates.value) {
      const objectType = key.split(':')[0] as ObjectType
      if (!keepSet.has(objectType)) {
        for (const u of updates) pendingIdToKey.delete(u.id)
        pendingUpdates.value.delete(key)
      }
    }
    // Clear temp IDs whose objects were wiped. An ID belongs to a cleared type
    // if it no longer appears in any kept type map (the cleared maps are empty now).
    for (const id of tempObjectIds) {
      let foundInKept = false
      for (const type of keepTypes) {
        if (objects.value.get(type)?.has(id)) {
          foundInKept = true
          break
        }
      }
      if (!foundInKept) {
        tempObjectIds.delete(id)
      }
    }
    bumpVersion(...clearedTypes)
    triggerRef(objects)
    triggerRef(pendingUpdates)
  }

  // Replace all objects — clears existing data then imports.
  // Used on sync to ensure server-side deletions are reflected.
  // Preserves pending updates that are newer than the server data (queued commands).
  // Preserves temp objects (added via set()) absent from the server payload —
  // these are optimistically-created objects whose create commands are still queued.
  //
  // Objects are inserted in chunks of REPLACE_CHUNK_SIZE. The clear and the first
  // chunk are always processed in the same synchronous call frame so consumers never
  // observe an empty pool. Subsequent chunks are scheduled via setTimeout(0) to yield
  // to the browser between each batch. Reactivity fires once after the final chunk.
  function replaceObjects(poolObjects: PoolObject[]): Promise<void> {
    // Build set of IDs present in the server payload
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

    // Snapshot temp objects not present in the server payload.
    // These are optimistically-created objects whose create commands are still
    // in the command queue — they must survive the sync to stay visible in the UI.
    // Objects that appear in the server payload are removed from tempObjectIds
    // (the server has confirmed them) and replaced by the authoritative server data.
    const tempObjectsToPreserve: PoolObject[] = []
    for (const id of tempObjectIds) {
      if (serverIds.has(id)) {
        // Server confirmed this object — no longer an unconfirmed temp
        tempObjectIds.delete(id)
      } else {
        // Still unconfirmed — find and preserve the object before clearing
        for (const typeMap of objects.value.values()) {
          const obj = typeMap.get(id)
          if (obj) {
            tempObjectsToPreserve.push(obj)
            break
          }
        }
      }
    }

    // All objects to insert: server data + preserved temp objects
    const allObjects: PoolObject[] = [...poolObjects, ...tempObjectsToPreserve]

    // Clear all type maps and insert the first chunk synchronously so that
    // consumers never observe an empty pool — the clear and first insertion
    // happen in the same call frame.
    for (const typeMap of objects.value.values()) {
      typeMap.clear()
    }
    const firstChunk = allObjects.slice(0, REPLACE_CHUNK_SIZE)
    for (const obj of firstChunk) {
      const typeMap = objects.value.get(obj.objectType)
      if (typeMap) {
        typeMap.set(obj.id, obj)
      }
    }

    // For small payloads (or when the first chunk covered everything), we're done
    if (allObjects.length <= REPLACE_CHUNK_SIZE) {
      bumpVersion(...OBJECT_TYPES)
      triggerRef(objects)
      triggerRef(pendingUpdates)
      notifyChange({ type: 'replace', objects: poolObjects })
      return Promise.resolve()
    }

    // Large payload: insert remaining chunks via setTimeout(0) so the browser
    // can paint frames between each batch. Reactivity fires once at the end.
    return new Promise<void>((resolve) => {
      let offset = REPLACE_CHUNK_SIZE

      function processNextChunk(): void {
        const chunk = allObjects.slice(offset, offset + REPLACE_CHUNK_SIZE)
        offset += REPLACE_CHUNK_SIZE

        for (const obj of chunk) {
          const typeMap = objects.value.get(obj.objectType)
          if (typeMap) {
            typeMap.set(obj.id, obj)
          }
        }

        if (offset < allObjects.length) {
          // More chunks remain — yield to the event loop then continue
          setTimeout(processNextChunk, 0)
        } else {
          // All chunks done — trigger reactivity once
          bumpVersion(...OBJECT_TYPES)
          triggerRef(objects)
          triggerRef(pendingUpdates)
          notifyChange({ type: 'replace', objects: poolObjects })
          resolve()
        }
      }

      setTimeout(processNextChunk, 0)
    })
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
    getAllCache.clear()
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
    cascadeRemove,
    replaceObjects,
    restorePendingUpdates,
    clearExcept,
    setReadTransform,
    $reset,
  }
})
