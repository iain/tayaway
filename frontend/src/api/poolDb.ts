import { openDB, type IDBPDatabase } from 'idb'
import type { PoolObject, ObjectType, PendingUpdate } from '@/types/pool'

// A scope is a partition of the cache. Personal data lives in PERSONAL_SCOPE
// and is shared across all workspaces; everything else lives in a
// per-workspace scope so other workspaces' data survives a switch.
export const PERSONAL_SCOPE = 'personal'
export function workspaceScope(workspaceId: string): string {
  return `workspace:${workspaceId}`
}

interface StoredObject {
  key: string
  scope: string
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
    indexes: { objectType: ObjectType; scope: string }
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

// Bump this when the sync protocol changes to invalidate stale caches.
// Bumped to 11 when the cache became multi-workspace; old caches lack the
// scope field and must be wiped on upgrade.
const CACHE_VERSION = 11

const CURRENT_WORKSPACE_META_KEY = 'currentWorkspaceId'
const CACHE_VERSION_META_KEY = 'cacheVersion'
const SYNCED_AT_META_PREFIX = 'syncedAt:'

let dbPromise: Promise<IDBPDatabase<PoolCacheDB>> | null = null

function getDb(): Promise<IDBPDatabase<PoolCacheDB>> {
  if (!dbPromise) {
    dbPromise = openDB<PoolCacheDB>('tayaway-pool-cache', 3, {
      upgrade(db, oldVersion, _newVersion, tx) {
        if (oldVersion < 1) {
          const store = db.createObjectStore('objects', { keyPath: 'key' })
          store.createIndex('objectType', 'objectType')
          db.createObjectStore('meta', { keyPath: 'key' })
        }
        if (oldVersion < 2) {
          db.createObjectStore('pendingUpdates', { keyPath: 'key' })
        }
        if (oldVersion < 3) {
          // Multi-workspace cache: old entries lack `scope` and use a
          // non-scoped key format. Wipe them and create the new index.
          const objectsStore = tx.objectStore('objects')
          objectsStore.clear()
          objectsStore.createIndex('scope', 'scope')
          tx.objectStore('meta').clear()
          tx.objectStore('pendingUpdates').clear()
        }
      },
    })
  }
  return dbPromise
}

function toKey(scope: string, objectType: string, id: string): string {
  return `${scope}::${objectType}:${id}`
}

export async function saveObjects(
  scope: string,
  objects: PoolObject[]
): Promise<void> {
  if (objects.length === 0) return
  const db = await getDb()
  const tx = db.transaction('objects', 'readwrite')
  for (const obj of objects) {
    tx.store.put({
      key: toKey(scope, obj.objectType, obj.id),
      scope,
      objectType: obj.objectType,
      id: obj.id,
      data: obj,
    })
  }
  await tx.done
}

export async function removeObjects(
  scope: string,
  entries: { objectType: string; id: string }[]
): Promise<void> {
  if (entries.length === 0) return
  const db = await getDb()
  const tx = db.transaction('objects', 'readwrite')
  for (const entry of entries) {
    tx.store.delete(toKey(scope, entry.objectType, entry.id))
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

/**
 * Replace one scope's objects atomically. Other scopes (other workspaces,
 * personal data) are left alone so a workspace full-sync doesn't wipe the
 * caches we want to keep hot.
 */
export async function replaceScope(
  scope: string,
  objects: PoolObject[],
  syncedAt?: string
): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta'], 'readwrite')

  const objectStore = tx.objectStore('objects')
  const scopeIndex = objectStore.index('scope')
  let cursor = await scopeIndex.openCursor(IDBKeyRange.only(scope))
  while (cursor) {
    cursor.delete()
    cursor = await cursor.continue()
  }

  for (const obj of objects) {
    objectStore.put({
      key: toKey(scope, obj.objectType, obj.id),
      scope,
      objectType: obj.objectType,
      id: obj.id,
      data: obj,
    })
  }

  tx.objectStore('meta').put({
    key: CACHE_VERSION_META_KEY,
    cacheVersion: CACHE_VERSION,
  })
  if (syncedAt) {
    tx.objectStore('meta').put({
      key: `${SYNCED_AT_META_PREFIX}${scope}`,
      syncedAt,
    })
  }
  await tx.done
}

export async function clearScope(scope: string): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta'], 'readwrite')
  const scopeIndex = tx.objectStore('objects').index('scope')
  let cursor = await scopeIndex.openCursor(IDBKeyRange.only(scope))
  while (cursor) {
    cursor.delete()
    cursor = await cursor.continue()
  }
  tx.objectStore('meta').delete(`${SYNCED_AT_META_PREFIX}${scope}`)
  await tx.done
}

interface ScopedSyncedAt {
  syncedAt: Map<string, string>
}

/**
 * Read only the lightweight metadata record from the cache.
 * Returns the last-active workspace, cache version, and a per-scope syncedAt
 * map (so a partial sync per workspace can use its own cursor).
 */
export async function loadMeta(): Promise<{
  currentWorkspaceId: string | null
  cacheVersion: number | null
  syncedAt: Map<string, string>
}> {
  const db = await getDb()
  const tx = db.transaction('meta', 'readonly')
  const all = await tx.store.getAll()
  let currentWorkspaceId: string | null = null
  let cacheVersion: number | null = null
  const syncedAt = new Map<string, string>()
  for (const entry of all) {
    if (entry.key === CURRENT_WORKSPACE_META_KEY) {
      currentWorkspaceId = entry.workspaceId ?? null
    } else if (entry.key === CACHE_VERSION_META_KEY) {
      cacheVersion = entry.cacheVersion ?? null
    } else if (entry.key.startsWith(SYNCED_AT_META_PREFIX) && entry.syncedAt) {
      syncedAt.set(entry.key.slice(SYNCED_AT_META_PREFIX.length), entry.syncedAt)
    }
  }
  return { currentWorkspaceId, cacheVersion, syncedAt }
}

/**
 * Read all cached objects of a single object type from a single scope.
 * Callers should yield to the event loop between successive type loads so the
 * browser can paint frames while the cache is being restored progressively.
 */
export async function loadObjectsByType(
  scope: string,
  objectType: ObjectType
): Promise<PoolObject[]> {
  const db = await getDb()
  const tx = db.transaction('objects', 'readonly')
  const scopeIndex = tx.store.index('scope')
  const stored = await scopeIndex.getAll(IDBKeyRange.only(scope))
  return stored
    .filter((s) => s.objectType === objectType)
    .map((s) => s.data)
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

export async function saveSyncedAt(
  scope: string,
  syncedAt: string
): Promise<void> {
  const db = await getDb()
  await db.put('meta', {
    key: `${SYNCED_AT_META_PREFIX}${scope}`,
    syncedAt,
  })
}

export async function setCurrentWorkspaceId(workspaceId: string): Promise<void> {
  const db = await getDb()
  await db.put('meta', { key: CURRENT_WORKSPACE_META_KEY, workspaceId })
}

export async function clearAll(): Promise<void> {
  const db = await getDb()
  const tx = db.transaction(['objects', 'meta', 'pendingUpdates'], 'readwrite')
  tx.objectStore('objects').clear()
  tx.objectStore('meta').clear()
  tx.objectStore('pendingUpdates').clear()
  await tx.done
}

export type { ScopedSyncedAt }
