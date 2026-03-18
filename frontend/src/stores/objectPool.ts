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
    { childType: 'rsvp', foreignKey: 'eventId' },
    { childType: 'expense', foreignKey: 'eventId' },
  ],
  datePoll: [{ childType: 'dateRange', foreignKey: 'datePollId' }],
  dateRange: [{ childType: 'vote', foreignKey: 'dateRangeId' }],
  settlement: [
    { childType: 'settlementTransfer', foreignKey: 'settlementId' },
  ],
  choreRoster: [{ childType: 'chore', foreignKey: 'choreRosterId' }],
  chore: [{ childType: 'choreAssignment', foreignKey: 'choreId' }],
  taskList: [{ childType: 'taskItem', foreignKey: 'taskListId' }],
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

  // Per-type version counters to limit reactivity invalidation scope
  const typeVersions = ref(
    new Map<ObjectType, number>(OBJECT_TYPES.map((type) => [type, 0]))
  )
  // Global version counter (for backwards compatibility and cross-type consumers)
  const version = ref(0)

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
    version.value++
    triggerRef(typeVersions)
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
          pendingUpdates.value.delete(pendingKey)
          changed = true
        }
      }

      // Update pool object if newer or doesn't exist
      if (!existing || isNewer(obj.updatedAt, existing.updatedAt)) {
        typeMap.set(obj.id, obj)
        imported.push(obj)
        changed = true
      }
    }
    // Trigger reactivity for nested Map changes
    if (changed) {
      const changedTypes = new Set(imported.map((o) => o.objectType))
      bumpVersion(...changedTypes)
      triggerRef(objects)
      triggerRef(pendingUpdates)
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
    bumpVersion(objectType)
    triggerRef(pendingUpdates)

    return pendingId
  }

  // Remove a specific pending update (for rollback)
  function removePending(pendingId: string): void {
    const changedTypes = new Set<ObjectType>()
    for (const [key, updates] of pendingUpdates.value.entries()) {
      const filtered = updates.filter((u) => u.id !== pendingId)
      if (filtered.length === 0) {
        pendingUpdates.value.delete(key)
        changedTypes.add(key.split(':')[0] as ObjectType)
      } else if (filtered.length !== updates.length) {
        pendingUpdates.value.set(key, filtered)
        changedTypes.add(key.split(':')[0] as ObjectType)
      }
    }
    if (changedTypes.size > 0) {
      bumpVersion(...changedTypes)
      triggerRef(pendingUpdates)
    }
  }

  // Check if an object has pending updates
  function hasPending(objectType: ObjectType, objectId: string): boolean {
    const pendingKey = `${objectType}:${objectId}`
    const pending = pendingUpdates.value.get(pendingKey)
    return Boolean(pending && pending.length > 0)
  }

  // Set an object directly (for creating new objects optimistically)
  function set<T extends ObjectType>(object: ObjectTypeMap[T]): void {
    const typeMap = objects.value.get(object.objectType)
    if (typeMap) {
      typeMap.set(object.id, object)
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
    // Also clear any pending updates
    pendingUpdates.value.delete(`${objectType}:${objectId}`)
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
        pendingUpdates.value.delete(`${type}:${id}`)
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
    // Clear pending updates for cleared types
    for (const [key] of pendingUpdates.value) {
      const objectType = key.split(':')[0] as ObjectType
      if (!keepSet.has(objectType)) {
        pendingUpdates.value.delete(key)
      }
    }
    bumpVersion(...clearedTypes)
    triggerRef(objects)
    triggerRef(pendingUpdates)
  }

  // Replace all objects — clears existing data then imports.
  // Used on sync to ensure server-side deletions are reflected.
  // Preserves pending updates that are newer than the server data (queued commands).
  function replaceObjects(poolObjects: PoolObject[]): void {
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
      if (newer.length === 0) {
        pendingUpdates.value.delete(key)
      } else {
        pendingUpdates.value.set(key, newer)
      }
    }

    // Clear all type maps
    for (const typeMap of objects.value.values()) {
      typeMap.clear()
    }

    // Import the new objects
    for (const obj of poolObjects) {
      const typeMap = objects.value.get(obj.objectType)
      if (typeMap) {
        typeMap.set(obj.id, obj)
      }
    }

    bumpVersion(...OBJECT_TYPES)
    triggerRef(objects)
    triggerRef(pendingUpdates)
    notifyChange({ type: 'replace', objects: poolObjects })
  }

  // Restore pending updates from cache (used on startup)
  function restorePendingUpdates(cached: Map<string, PendingUpdate[]>): void {
    if (cached.size === 0) return
    const restoredTypes = new Set<ObjectType>()
    for (const [key, updates] of cached) {
      pendingUpdates.value.set(key, updates)
      restoredTypes.add(key.split(':')[0] as ObjectType)
    }
    bumpVersion(...restoredTypes)
    triggerRef(pendingUpdates)
  }

  // Reset the store
  function $reset(): void {
    objects.value = createEmptyStorage()
    pendingUpdates.value = new Map()
    getAllCache.clear()
  }

  return {
    // State
    objects,
    pendingUpdates,
    version,
    typeVersions,
    stats,

    // Methods
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
