import { ref, computed, triggerRef } from 'vue'
import { defineStore } from 'pinia'
import {
  OBJECT_TYPES,
  type ObjectType,
  type ObjectTypeMap,
  type PoolObject,
  type PendingUpdate,
} from '@/types/pool'

// Helper to compare ISO8601 timestamps
function isNewer(a: string, b: string): boolean {
  return new Date(a).getTime() > new Date(b).getTime()
}

// Generate unique ID for pending updates
let pendingIdCounter = 0
function generatePendingId(): string {
  return `pending_${++pendingIdCounter}_${Date.now()}`
}

// Create empty storage maps from OBJECT_TYPES
function createEmptyStorage(): Map<ObjectType, Map<string, PoolObject>> {
  return new Map(OBJECT_TYPES.map((type) => [type, new Map()]))
}

export const useObjectPoolStore = defineStore('objectPool', () => {
  // Storage: Map<ObjectType, Map<id, object>>
  const objects = ref(createEmptyStorage())

  // Pending optimistic updates: Map<"type:id", PendingUpdate[]>
  const pendingUpdates = ref(new Map<string, PendingUpdate[]>())

  // Version counter to force reactivity - incremented on any change
  const version = ref(0)

  // Import objects from API response - no parsing needed
  function importObjects(poolObjects: PoolObject[]): void {
    let changed = false
    for (const obj of poolObjects) {
      const typeMap = objects.value.get(obj.objectType)
      if (!typeMap) continue

      const existing = typeMap.get(obj.id)
      const pendingKey = `${obj.objectType}:${obj.id}`
      const hadPending = pendingUpdates.value.has(pendingKey)

      // Always clear pending updates - server response is authoritative
      if (hadPending) {
        pendingUpdates.value.delete(pendingKey)
        changed = true
      }

      // Update pool object if newer or doesn't exist
      if (!existing || isNewer(obj.updatedAt, existing.updatedAt)) {
        typeMap.set(obj.id, obj)
        changed = true
      }
    }
    // Trigger reactivity for nested Map changes
    if (changed) {
      version.value++
      triggerRef(objects)
      triggerRef(pendingUpdates)
    }
  }

  // Get an object by type and id, with pending updates merged
  function get<T extends ObjectType>(
    type: T,
    id: string
  ): ObjectTypeMap[T] | undefined {
    // Access version to establish reactivity dependency
    void version.value

    const typeMap = objects.value.get(type)
    if (!typeMap) return undefined

    const server = typeMap.get(id) as ObjectTypeMap[T] | undefined
    if (!server) return undefined

    const pendingKey = `${type}:${id}`
    const pending = pendingUpdates.value.get(pendingKey)
    if (!pending?.length) return server

    // Merge all pending changes onto the server data
    return pending.reduce(
      (merged, update) => ({ ...merged, ...update.changes }),
      { ...server }
    )
  }

  // Get raw server object without pending updates
  function getServer<T extends ObjectType>(
    type: T,
    id: string
  ): ObjectTypeMap[T] | undefined {
    const typeMap = objects.value.get(type)
    return typeMap?.get(id) as ObjectTypeMap[T] | undefined
  }

  // Get all objects of a type
  function getAll<T extends ObjectType>(type: T): ObjectTypeMap[T][] {
    const typeMap = objects.value.get(type)
    if (!typeMap) return []

    return Array.from(typeMap.values()).map((obj) => {
      const pendingKey = `${type}:${obj.id}`
      const pending = pendingUpdates.value.get(pendingKey)
      if (!pending?.length) return obj as ObjectTypeMap[T]

      return pending.reduce(
        (merged, update) => ({ ...merged, ...update.changes }),
        { ...obj }
      ) as ObjectTypeMap[T]
    })
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
    version.value++
    triggerRef(pendingUpdates)

    return pendingId
  }

  // Remove a specific pending update (for rollback)
  function removePending(pendingId: string): void {
    let changed = false
    for (const [key, updates] of pendingUpdates.value.entries()) {
      const filtered = updates.filter((u) => u.id !== pendingId)
      if (filtered.length === 0) {
        pendingUpdates.value.delete(key)
        changed = true
      } else if (filtered.length !== updates.length) {
        pendingUpdates.value.set(key, filtered)
        changed = true
      }
    }
    if (changed) {
      version.value++
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
      version.value++
      triggerRef(objects)
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
    version.value++
    triggerRef(objects)
    triggerRef(pendingUpdates)
  }

  // Computed to get pool stats (useful for debugging)
  const stats = computed(() => {
    const result = {} as Record<ObjectType, number>
    for (const type of OBJECT_TYPES) {
      result[type] = objects.value.get(type)?.size ?? 0
    }
    return result
  })

  // Reset the store
  function $reset(): void {
    objects.value = createEmptyStorage()
    pendingUpdates.value = new Map()
  }

  return {
    // State
    objects,
    pendingUpdates,
    version,
    stats,

    // Methods
    importObjects,
    get,
    getServer,
    getAll,
    getMany,
    addPending,
    removePending,
    hasPending,
    set,
    remove,
    $reset,
  }
})
