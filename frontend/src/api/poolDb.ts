import { openDB, type IDBPDatabase } from 'idb'
import type { PoolObject, ObjectType, PendingUpdate } from '@/types/pool'

interface StoredObject {
  key: string
  objectType: ObjectType
  id: string
  data: PoolObject
}

interface StoredPendingEntry {
  key: string
  updates: PendingUpdate[]
}

interface MetaEntry {
  key: string
  workspaceId?: string
  syncedAt?: string
  cacheVersion?: number
}

interface PoolCacheDB {
  objects: {
    key: string
    value: StoredObject
    indexes: { objectType: ObjectType }
  }
  meta: {
    key: string
    value: MetaEntry
  }
  pendingUpdates: {
    key: string
    value: StoredPendingEntry
  }
}

// Bump this when the sync protocol changes to invalidate stale caches
const CACHE_VERSION = 5

let dbPromise: Promise<IDBPDatabase<PoolCacheDB>> | null = null

function getDb(): Promise<IDBPDatabase<PoolCacheDB>> {
  if (!dbPromise) {
    dbPromise = openDB<PoolCacheDB>('tayaway-pool-cache', 2, {
      upgrade(db, oldVersion) {
        if (oldVersion < 1) {
          const store = db.createObjectStore('objects', { keyPath: 'key' })
          store.createIndex('objectType', 'objectType')
          db.createObjectStore('meta', { keyPath: 'key' })
        }
        if (oldVersion < 2) {
          db.createObjectStore('pendingUpdates', { keyPath: 'key' })
        }
      },
    })
  }
  return dbPromise
}

function toKey(objectType: string, id: string): string {
  return `${objectType}:${id}`
}

export async function saveObjects(objects: PoolObject[]): Promise<void> {
  if (objects.length === 0) return
  const db = await getDb()
  const tx = db.transaction('objects', 'readwrite')
  for (const obj of objects) {
    const stored: StoredObject = {
      key: toKey(obj.objectType, obj.id),
      objectType: obj.objectType,
      id: obj.id,
      data: obj,
    }
    tx.store.put(stored)
  }
  await tx.done
}

export async function removeObjects(
  entries: { objectType: string; id: string }[]
): Promise<void> {
  if (entries.length === 0) return
  const db = await getDb()
  const tx = db.transaction('objects', 'readwrite')
  for (const entry of entries) {
    tx.store.delete(toKey(entry.objectType, entry.id))
  }
  await tx.done
}

export async function savePendingUpdates(
  entries: Map<string, PendingUpdate[]>
): Promise<void> {
  const db = await getDb()
  const tx = db.transaction('pendingUpdates', 'readwrite')
  tx.store.clear()
  for (const [key, updates] of entries) {
    tx.store.put({ key, updates })
  }
  await tx.done
}

export async function loadPendingUpdates(): Promise<
  Map<string, PendingUpdate[]>
> {
  const db = await getDb()
  const stored = await db.getAll('pendingUpdates')
  const map = new Map<string, PendingUpdate[]>()
  for (const entry of stored) {
    map.set(entry.key, entry.updates)
  }
  return map
}

export async function replaceAll(
  workspaceId: string,
  objects: PoolObject[],
  syncedAt?: string
): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta', 'pendingUpdates'], 'readwrite')
  tx.objectStore('objects').clear()
  tx.objectStore('pendingUpdates').clear()
  tx.objectStore('meta').put({ key: 'workspace', workspaceId })
  tx.objectStore('meta').put({
    key: 'cacheVersion',
    cacheVersion: CACHE_VERSION,
  })
  if (syncedAt) {
    tx.objectStore('meta').put({ key: 'syncedAt', syncedAt })
  }
  const objectStore = tx.objectStore('objects')
  for (const obj of objects) {
    objectStore.put({
      key: toKey(obj.objectType, obj.id),
      objectType: obj.objectType,
      id: obj.id,
      data: obj,
    })
  }
  await tx.done
}

export async function loadAll(): Promise<{
  workspaceId: string | null
  syncedAt: string | null
  cacheVersion: number | null
  objects: PoolObject[]
  pendingUpdates: Map<string, PendingUpdate[]>
}> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta', 'pendingUpdates'], 'readonly')
  const meta = await tx.objectStore('meta').get('workspace')
  const syncedAtMeta = await tx.objectStore('meta').get('syncedAt')
  const versionMeta = await tx.objectStore('meta').get('cacheVersion')
  const stored = await tx.objectStore('objects').getAll()
  const pendingStored = await tx.objectStore('pendingUpdates').getAll()

  const pendingMap = new Map<string, PendingUpdate[]>()
  for (const entry of pendingStored) {
    pendingMap.set(entry.key, entry.updates)
  }

  return {
    workspaceId: meta?.workspaceId ?? null,
    syncedAt: syncedAtMeta?.syncedAt ?? null,
    cacheVersion: versionMeta?.cacheVersion ?? null,
    objects: stored.map((s) => s.data),
    pendingUpdates: pendingMap,
  }
}

/**
 * Read only the lightweight metadata record from the cache.
 * This is fast even on large datasets because it reads three small records
 * rather than iterating over every cached object.
 */
export async function loadMeta(): Promise<{
  workspaceId: string | null
  syncedAt: string | null
  cacheVersion: number | null
}> {
  const db = await getDb()
  const tx = db.transaction('meta', 'readonly')
  const meta = await tx.store.get('workspace')
  const syncedAtMeta = await tx.store.get('syncedAt')
  const versionMeta = await tx.store.get('cacheVersion')
  return {
    workspaceId: meta?.workspaceId ?? null,
    syncedAt: syncedAtMeta?.syncedAt ?? null,
    cacheVersion: versionMeta?.cacheVersion ?? null,
  }
}

/**
 * Read all cached objects of a single object type using the objectType index.
 * Callers should yield to the event loop between successive type loads so the
 * browser can paint frames while the cache is being restored progressively.
 */
export async function loadObjectsByType(
  objectType: ObjectType
): Promise<PoolObject[]> {
  const db = await getDb()
  const tx = db.transaction('objects', 'readonly')
  const stored = await tx.store.index('objectType').getAll(objectType)
  return stored.map((s) => s.data)
}

/**
 * Read all pending updates from the cache.
 */
export async function loadPendingUpdatesFromDb(): Promise<
  Map<string, PendingUpdate[]>
> {
  const db = await getDb()
  const stored = await db.getAll('pendingUpdates')
  const map = new Map<string, PendingUpdate[]>()
  for (const entry of stored) {
    map.set(entry.key, entry.updates)
  }
  return map
}

export { CACHE_VERSION }

export async function saveSyncedAt(syncedAt: string): Promise<void> {
  const db = await getDb()
  await db.put('meta', { key: 'syncedAt', syncedAt })
}

export async function clearAll(): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta', 'pendingUpdates'], 'readwrite')
  tx.objectStore('objects').clear()
  tx.objectStore('meta').clear()
  tx.objectStore('pendingUpdates').clear()
  await tx.done
}
